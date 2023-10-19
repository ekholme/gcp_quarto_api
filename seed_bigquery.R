library(bigrquery)
library(palmerpenguins)

x <- bq_dataset("ee-proj-123", "penguins_data")

bq_dataset_create(x)

y <- bq_table(x, "penguins")

bq_table_create(y, fields = penguins)

bq_table_upload(y, penguins)
