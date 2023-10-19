#* Render an Rmd report
#* @serializer html
#* @param n number of rows to display
#* @get /report
function(n_row = 10) {
    tmp <- paste0(sample(c(letters, 0:9), 16, replace = TRUE), collapse = "")
    tmp <- paste0(tmp, ".html")
    quarto::quarto_render("report_template.qmd",
        output_file = tmp,
        # output_format = "html",
        execute_params = list(n_row = n_row)
    )

    readBin(tmp, "raw", n = file.info(tmp)$size)
}
 