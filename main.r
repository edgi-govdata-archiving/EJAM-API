# Based on https://github.com/petegordon/RCloudRun
library(plumber)

r <- plumb("rest_controller.r")

# Report the installed EJAM package version in the Swagger/OpenAPI metadata,
# and preserve the build-time git ref separately as provenance.
r <- plumber::pr_set_api_spec(r, function(spec) {
  spec$info$version <- as.character(utils::packageVersion("EJAM"))

  ejam_ref <- Sys.getenv("EJAM_VERSION")
  if (nzchar(ejam_ref)) {
    description <- spec$info$description
    if (is.null(description) || length(description) != 1L || is.na(description)) {
      description <- ""
    }
    separator <- if (nzchar(description)) "\n\n" else ""
    spec$info$description <- paste0(
      description,
      separator,
      "Built from EJAM ref: ",
      ejam_ref
    )
  }

  spec
})

r$run(port=8080, host="0.0.0.0")
