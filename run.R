library(plumber)

pr("plumber.R") |>
    pr_run(port = 8080, host = "0.0.0.0")
# note -- if you want to test this locally (not in a docker container),
# don't include the host argument 