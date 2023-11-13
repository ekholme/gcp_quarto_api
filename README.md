# Deploying a Web Service to Render Reports with Plumber, Quarto, Docker, and Google Cloud


This repo provides a step-by-step guide for deploying an API that can render parameterized Quarto reports. It uses the following components:

- R, and particularly the [{plumber}](https://www.rplumber.io/) package
- [Quarto](https://quarto.org/)
- [Docker](https://docker.com)
- Google Cloud products, including [BigQuery](https://cloud.google.com/bigquery), [Cloud Run](https://cloud.google.com/run), [Cloud Build](https://cloud.google.com/build), [Artifact Registry](https://cloud.google.com/artifact-registry), and [Source Repositories](https://cloud.google.com/source-repositories/docs)


## Motivation

I write reports fairly often in my job, and I imagine other R developers do as well. This tends to include making different versions of the same report for different groups -- in my case, making reports for each school in the division (or for each teacher, or class, etc). And in addition to rendering these reports, getting them to appropriate stakeholders also matters. If there are a small handful of reports, then just sending emails can work, but this sort of manual process quickly becomes intractable as the number of reports grows.

A more efficient way to distribute reports is by letting stakeholders hit an API and having the reports be rendered on-demand. But this also introduces complexity in that you have to deploy an API. So, the purpose of this guide is to walk you through a process for setting up an API that can render parameterized reports. The end-product is mean to be pretty minimal, but hopefully the extensions are obvious for those of you who want to pick up and run with this.

## Prerequisites

I'm going to assume the following of the person reading this:

- You're an intermediate R user;
- You have a Google Cloud account (including a billing account!) set up already;
- You have Quarto, R, Git, and the gcloud CLI installed on your computer; and
- You have some familiarity with Git

We'll use Docker as well, but through Cloud Build, so you don't necessarily need it on your computer. That said, it doesn't hurt to have Docker Desktop installed, and some familiarity with Docker will help you here.

I'm not going to walk through how to install the software mentioned above or how to create a Google Cloud account. If you need help with any of that, I'd suggest checking out the official documentation for each of those components.

## Workflow, Final Product, and Conventions

Ultimately, we're going to deploy a minimal API. Users will be able to navigate to the `/report` endpoint of that API to get a report rendered for them. Users will be able to specify how many rows of data are shown in the report via a query parameter, e.g. `/report?n_row=12`.

More specifically, the project will entail:

- Specifying the API using R and plumber;
- Loading sample data (from the [{palmerpenguins}](https://allisonhorst.github.io/palmerpenguins/) R package) into BigQuery;
- Creating a report template using Quarto;
- Pushing source code to a Google Cloud Source repository using git;
- Building a container image (that will ultimately run the app) using Cloud Build and Artifact Registry; and
- Deploying the resulting image as a container to Cloud Run

All of the files needed to do this will be included in the repository. Rather than including `.sh` or `.ps1` files to specify command-line arguments, though, I'm just going to include these commands here. I'm also going to use placeholders for project ids, repo ids, and project numbers. I'll denote these placeholders in ALL_CAPS.

Finally, it's possible to interact with Google Cloud through the console the and graphical user interfact. You can choose to do this if you'd like, and it might be easier if you're newer to Google Cloud. But I'm going to interact with Google Cloud through the gcloud CLI, which makes the process more replicable.

## Steps

### Create a Project

On your local machine, you'll want to create a new folder to house your project

``` shell
mkdir MY-PROJECT
cd MY-PROJECT
```

If you haven't used the gcloud CLI before, you'll need to initialize it via:

``` shell
gcloud init
```

Then, you want to create a new Google Cloud project using gcloud:

``` shell
gcloud projects create MY-PROJECT
```

### Load Example Data into BigQuery

In a real use case, you'll probably want your API to access data from a database. So we're going to simulate that here using Google's BigQuery -- a datawarehouse designed for data analytics.

The code in the `seed_bigquery.R` file will load the {palmerpenguins} data into a BigQuery table that we can access from our API. If it's your first time using the `{bigrquery}` package, you might be prompted to do some housekeeping/granting access to resources.

``` r
#install.packages(c("bigrquery", "palmerpenguins"))
library(bigrquery)
library(palmerpenguins)

x <- bq_dataset("MY-PROJECT", "penguins_data")

bq_dataset_create(x)

y <- bq_table(x, "penguins")

bq_table_create(y, fields = penguins)

bq_table_upload(y, penguins)

```

This will create a new dataset in your project, then create a new table in that dataset, then upload the palmer penguins data into the table.

You can navigate to BigQuery in your Google Cloud console to confirm that the data uploaded.

### Create a Report Template

Next, we want to create a report template. This will define what gets rendered when users interact with our API.

We'll use Quarto for this, so the file will be a `.qmd` file. And we'll specify one parameter, `n_row`, that users can set to determine how many rows of data are included in the report, but this would obviously be something more meaningful in a real application.

You can see the template in the `report_template.qmd` file, but it's included below as well:

```` markdown
---
title: "My Report"
params:
  n_row: 10
format:
  html:
    embed-resources: true
---

This report will print `r params$n_row` rows from the palmer penguins dataset

```{{r}}
library(DBI)
library(bigrquery)
library(glue)


 n <- min(c(344, as.numeric(params$n_row)))
 proj <- "MY-PROJECT"
 ds <- "penguins_data"
 tbl <- "penguins"

 con <- dbConnect(
     bigrquery::bigquery(),
     project = proj,
     dataset = ds
 )

 q <- glue_sql("
     SELECT *
     FROM `MY-PROJECT.penguins_data.penguins`
     LIMIT {n}
 ", .con = con)

 res <- dbGetQuery(con, q)

 res 
```

````

### Create a Plumber Endpoint

Now that we have a report template, we want to define an API endpoint that users can hit to generate on-demand reports. To do that, we'll use the `{plumber}` R package.

Plumber is kinda like `{roxygen2}` in that it uses specially-formatted comments to define behaviors. Roxygen does this for package documentation, and plumber does this for API behaviors.

You can define an endpoint for your API using a series of these special comments, denoted with #*, and then a function definition

For example, we can define an endpoint that echoes back the message the user passed in like so (note that this example comes from the `{plumber}` [docs](https://www.rplumber.io/)):

``` r
#* Echo back the input
#* @param msg The message to echo
#* @get /echo
function(msg="") {
  list(msg = paste0("The message is: '", msg, "'"))
}
```

Where the `@param` tag defines a query parameter that can be passed to the function, and the `@get` tag specifices that the subsequent function will be called on GET requests to the `/echo` endpoint

We can define an endpoint that will render our Quarto report template like so:

``` r
#* Render an Rmd report
#* @serializer html
#* @param n number of rows to display
#* @get /report
function(n_row = 10) {
    tmp <- paste0(sample(c(letters, 0:9), 16, replace = TRUE), collapse = "")
    tmp <- paste0(tmp, ".html")
    quarto::quarto_render("report_template.qmd",
        output_file = tmp,
        execute_params = list(n_row = n_row)
    )

    readBin(tmp, "raw", n = file.info(tmp)$size)
}

```

This will render the Quarto report as a temporary file (sort of) and then read that temporary file. I say it's sort of a temporary file because our Docker container will trash any files it creates once it shuts down, but the file isn't *truly* temporary (if you run this on your machine, the file will persist until you delete it).

The code above is in the `plumber.R` file in this repo.

That code just defines the endpoint, but we also need something that will set up and run the API. This is what the code in `run.R` does:

``` r
library(plumber)

pr("plumber.R") |>
    pr_run(port = 8080, host = "0.0.0.0")
# note -- if you want to test this locally (not in a docker container),
# don't include the host argument 

```

Plumber is doing all of the heavy lifting here -- we're just telling it which file to reference in `pr()` (we want it to create endpoints defined in the `plumber.R` file) and providing the port and host we want it to run on. EZ game.

At this point, we've done everything we need to do in R and Quarto. We've loaded data into BigQuery (n.b. that we could have done this in lots of different ways), created a report template, and created an API that users can access to render reports.

Now we need to shift over to thinking about how to deploy it.

### Create a Cloud Source Repository and Push Code

Cloud Source Repositories is Google's service for hosting private git repos. I'm going to use that here because that's what I use at work, but you can use Github if you'd prefer (this will change some of the options in the Cloud Build step below).

We can create a new Google repo from the command line with gcloud as follows:

``` shell
gcloud source repos create MY-REPO --project=MY-PROJECT
```

Then you do the usual git workflow for pushing code

``` shell
git add .
git commit -m "my commit message"
git remote add origin https://source.developers.google.com/p/MY-PROJECT/r/MY-REPO

git push --all origin
```

Again, depending on how you've configured gcloud and git, you might have to do some extra authentication stuff here to ensure git has the appropriate credentials to push to Google Cloud. If you use Windows and run into issues, you might try `cmd` rather than `powershell`


### Create a Dockerfile

Dockerfiles are how you specify exactly what should be included in Docker images. If you're not super familiar with them, there are oodles of resources and tutorials on them, so I'm not going to try to reproduce those. Other people would do much better than I would.

At a very high level, though, Dockerfiles allow us to start with a base image (like an operating system such as Debian, or an OS with some other packages/libraries already installed), then systematically modify that base image until it meets our needs. You do this by defining operations that will run via the command line of the base image.

If you're an intermediate Linux user like me, a lot of your Dockerfile will be copy/pasted and slightly modified from other Dockerfiles you find online. Maybe this leaves you building containers that are bigger than they need to be, but there are worse sins.

Nevertheless. If you're an R user, the [Rocker project](https://rocker-project.org/) defines a bunch of containers useful for R folks. We'll start with their [verse](https://github.com/rocker-org/rocker-versioned2/blob/master/dockerfiles/verse_devel.Dockerfile) image for this project, which provides R and some OS libraries for rendering reports. 

From there, we'll download and install Quarto, copy necessary files over, install R packages, expose a port, and run our `run.R` file:

``` Dockerfile

ARG R_VER="latest"

FROM rocker/verse:${R_VER} 

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget

RUN wget https://github.com/quarto-dev/quarto-cli/releases/download/v1.3.450/quarto-1.3.450-linux-amd64.deb -O ~/quarto.deb

# Install the latest version of Quarto
RUN apt-get install --yes ~/quarto.deb

# Remove the installer
RUN rm ~/quarto.deb

COPY . .

# install r pkgs
RUN install2.r --error --skipinstalled --ncpus -1 \
    glue \
    DBI \
    bigrquery \
    plumber \
    quarto 

ENV PORT 8080

EXPOSE ${PORT}

ENTRYPOINT ["Rscript", "run.R"]

```

### Create a cloudbuild.yaml file

The Dockerfile we just created contains instructions for building an image that will run our application. Now, we need a service that can execute these instructions and deploy the image we build. We're going to use Google's Cloud Build to do this. Cloud Build is a continuous integration/continuous deployment (CI/CD) service that can help build and deploy software.

There are multiple different ways to interact with Cloud Build, but my preferred way is through a `cloudbuild.yaml` file. This file contains instructions that Cloud Build will execute for us. In this case, we're going to specify 3 steps:

1. Build a Docker image (using the Dockerfile we just wrote);
2. Push the image to Google Artifact Registry (a service that stores images, similar to Dockerhub); and
3. Deploy our image to Cloud Run (a serverless deployment service that runs containers)

Here's what the file looks like:

```` yaml
steps:
  #docker build 
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t',
            'us-east4-docker.pkg.dev/${PROJECT_ID}/demo-repo/demo-image:$COMMIT_SHA',
            '.']
  #docker push to artifact registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'us-east4-docker.pkg.dev/${PROJECT_ID}/demo-repo/demo-image:$COMMIT_SHA']

  #deploy the container to cloud run
  - name: 'gcr.io/cloud-builders/gcloud'
    args: ['run', 'deploy', 'img', '--image', 'us-east4-docker.pkg.dev/${PROJECT_ID}/demo-repo/demo-image:$COMMIT_SHA', '--region', 'us-east4', '--max-instances=1', '--min-instances=0', '--allow-unauthenticated']

````

You can see these instructions specified in the `cloudbuild.yaml` file. These are command-line arguments that the named services will run for us. For instance, the first step calls `docker build` along with some other arguments that control the build. The 3rd step calls `gcloud run deploy` and also specifies that:

- We want to deploy a service called "img";
- We want to deploy an image from the "us-east4-docker..." URL (which is where we pushed our image earlier);
- We want to deploy in the us-east4 region;
- We want a maximum of 1 instance and a minimum of 0 (you may want a different configuration for a real application); and
- We want to allow unauthenticated traffic

You may want to lookup additional arguments you can pass to docker or gcloud in their official documentation.

### gcloud Housekeeping

We mostly have the bones of our project set up now, but we need to do some housekeeping via gcloud. This includes enabling some services, granting appropriate permissions to our [service accounts](https://cloud.google.com/iam/docs/service-account-overview) (think: automated accounts that you delegate to run services for you), and creating a repository where the image we're building will be stored.

#### Enable Cloud Build and Cloud Run

By default, when you create a Google Cloud project, most services are disabled, and you need to enable them before you can use them. So we'll enable Cloud Build and Cloud Run here (note -- you're not billed for enabling services; only for using them)

``` shell
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
```

#### Create an Artifact Registry Repository

The artifact repository specified in the `cloudbuild.yaml` file above needs to exist for us to be able to push an image to it. So let's do that:

``` shell
gcloud artifacts repositories create demo-repo --repository-format docker --location us-east4 --project=MY-PROJECT
```
This will also prompt us to enable the Artifact Registry API if we haven't already done so.

#### Grant Permissions to Service Account

Google Cloud will generate a default service account for your project, and that's the one we'll use here. We need to grant that service account a few permissions that will allow it to complete the build, push, and deploy steps above:

``` shell
gcloud projects add-iam-policy-binding MY-PROJECT --member="serviceAccount:MY-PROJECT-NUMBER@cloudbuild.gserviceaccount.com"  --role=roles/run.admin

gcloud projects add-iam-policy-binding MY-PROJECT --member="serviceAccount:MY-PROJECT-NUMBER@cloudbuild.gserviceaccount.com" --role=roles/iam.serviceAccountUser

```

You'll notice that the service account is designated with your project number. If you don't know this (and why would you?), you can find it via:

``` shell
gcloud projects list
```

### Create a Build Trigger

Last step! So far, we've specified an API that we want to deploy (using R, plumber, and Quarto), we've described an image (via Docker) that we'll use to run this API, and we've configured various Google Cloud services to build and deploy this service.

The last thing we need to do is create a build trigger. The build trigger will tell Cloud Build when to execute the steps described in `cloudbuild.yaml`. There are a few approaches to doing this, but we're going to set our trigger to initiate a build whenever we push a commit to the master branch of our remote git repository.

We can do this via gcloud like so:

```bash
gcloud builds triggers create cloud-source-repositories --repo="MY-REPO" --project=MY-PROJECT  --branch-pattern="^master$" --name="push-master" --build-config="cloudbuild.yaml"
```

Hopefully the arguments in that command are fairly self-explanatory, but it does exactly what it we said earlier -- it'll execute the steps in `cloudbuild.yaml` whenever we push code to the master branch of "MY-REPO" (or whatever you named your repository). Note that one of the arguments specifies `cloud-source-repositories` -- if you're using a Github repo instead, you'd want to use `github` here instead.

## Try it Out!

That's it. Now, we just need to push some code to our source repository, the everything should work.

If we do the usual git dance (add, commit, push) and then navigate to the Google Cloud Build dashboard, you can follow along with the logs as your build executes. Once it's done, you should get a message showing you the URL where the API is deployed. Navigate to that `/report` endpoint of that URL and you should get a report to render, e.g.:

`my-service-url.run.app/report`

or

`my-service-url.run.app/report?n_row=12`

Rendering your report might take a few seconds, but ultimately you should get a *very minimal* Quarto report that pulls in the penguins data from BigQuery.

## Tear Down

To make sure you don't continue to incur charges, you probably want to tear down the project. You can do this via:

``` shell
gcloud projects delete MY-PROJECT
```

## Troubleshooting

Running all of the above should work for you, but if you run into any issues, `gcloud`, the Cloud Build logs, and the Cloud Run logs will all give you error messages that should (hopefully) help you diagnose any problems.

## Extensions

Obviously, this application isn't really useful on its own -- it's meant to show you the skeleton for setting up an application that is useful. As you modify and extend this, you'll potentially need to install additional R packages or additional system libraries, both of which will require modifying the Dockerfile. If you're like me, this will entail some trial and error, so it's probably a better approach to test these modifications and builds locally (via Docker Desktop) than in the cloud.

I hope this guide helps folks in the R community! Feel free to open an issue in this repo or create a pull request to improve this guide.