
ARG QUARTO_VERSION="latest"

FROM ghcr.io/quarto-dev/quarto:${QUARTO_VERSION} AS QUARTO

FROM rocker/r-ver:4.3

RUN apt update && apt install -y pandoc

COPY --from=QUARTO /usr/local/bin/quarto /usr/local/bin/quarto

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
