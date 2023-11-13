#install.packages(c("bigrquery", "palmerpenguins"))
library(bigrquery)
library(palmerpenguins)

x <- bq_dataset("MY-PROJECT", "penguins_data")

bq_dataset_create(x)

y <- bq_table(x, "penguins")

bq_table_create(y, fields = penguins)

bq_table_upload(y, penguins)
