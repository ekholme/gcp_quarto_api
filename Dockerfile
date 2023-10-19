ARG QUARTO_VERSION="latest"

FROM ghcr.io/quarto-dev/quarto:${QUARTO_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y r-base

RUN Rscript -e "install.packages(c('plumber', 'quarto', 'DBI', 'bigrquery', 'glue'))"

COPY . .

ENV PORT 8080

EXPOSE ${PORT}

ENTRYPOINT ["Rscript", "run.R"]