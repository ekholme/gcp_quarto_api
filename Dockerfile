
ARG R_VER="latest"
ARG QUARTO_VERSION="1.3.450"

FROM rocker/verse:${R_VER} 

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget

RUN wget https://github.com/quarto-dev/quarto-cli/releases/download/v$QUARTO_VERSION/quarto-$QUARTO_VERSION-linux-amd64.deb -O ~/quarto.deb

# Install the latest version of Quarto
RUN apt-get install --yes ~/quarto.deb

# Remove the installer
RUN rm ~/quarto.deb

COPY . .

RUN install2.r --error --skipinstalled --ncpus -1 \
    glue \
    DBI \
    bigrquery \
    plumber \
    quarto 

ENV PORT 8080

EXPOSE ${PORT}

ENTRYPOINT ["Rscript", "run.R"]
