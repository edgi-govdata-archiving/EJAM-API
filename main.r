# Based on https://github.com/petegordon/RCloudRun
library(plumber)

r <- plumb("rest_controller.r")

# Report the EJAM version used by this API in the Swagger/OpenAPI metadata.
# The Docker image sets EJAM_VERSION; local runs fall back to the installed
# package version.
r <- plumber::pr_set_api_spec(r, function(spec) {
  spec$info$version <- Sys.getenv(
    "EJAM_VERSION",
    unset = as.character(utils::packageVersion("EJAM"))
  )
  spec
})

r$run(port=8080, host="0.0.0.0")
