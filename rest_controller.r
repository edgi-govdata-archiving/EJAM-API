# Load necessary libraries
library(rlang)
library(plumber)
library(EJAM)
library(geojsonsf)
library(jsonlite)
library(sf)

# Centralized error handling function
handle_error <- function(message, type = "json") {
  if (type == "html") {
    return(paste0("<html><body><h3>Error</h3><p>", message, "</p></body></html>"))
  }
  return(list(error = message))
}

# The fipper function processes FIPS inputs, converting area names (e.g., states)
# to the appropriate FIPS codes for the specified scale (e.g., counties).
fipper <- function(area, scale = "blockgroup") {
  fips_area <- tryCatch(
    name2fips(area),
    warning = function(w) {
      # If a warning occurs, it's likely the input is already a FIPS code.
      return(area)
    }
  )
  
  # Determine the type of the provided FIPS code.
  fips_type <- fipstype(fips_area)[1]
  
  if (fips_type == scale) {
    return(fips_area)
  }
  
  # Convert the FIPS code to the desired scale.
  switch(scale,
         "county" = fips_counties_from_statefips(fips_area),
         "blockgroup" = fips_bgs_in_fips(fips_area),
         fips_area # Default to returning the original FIPS if the scale is not recognized.
  )
}

# The ejamit_interface function serves as a unified interface for the ejamit function,
# handling various input methods such as latitude/longitude, shapes (SHP), and FIPS codes.
ejamit_interface <- function(area, method, buffer = 0, scale = "blockgroup", endpoint="report") {
  # Validate buffer size to ensure it's within a reasonable limit.

  if (!is.numeric(buffer) || buffer > 15) {
    stop("Please select a buffer of 15 miles or less.")
  }
  
  # Process the request based on the specified method.
  switch(method,
         "latlon" = {
           # Ensure the area is a data frame before passing it to ejamit.
           if (!is.data.frame(area)) {
             stop("Invalid coordinates provided.")
           }
           ejamit(sitepoints = area, radius = buffer)
         },
         "SHP" = {
           # Convert the GeoJSON input to an sf object.
           sf_area <- tryCatch(
             geojson_sf(area),
             error = function(e) stop("Invalid GeoJSON provided.")
           )
           ejamit(shapefile = sf_area, radius = buffer)
         },
         "FIPS" = {
           # Process the FIPS code using the fipper function.
           if (endpoint == "data"){
             fips_codes <- fipper(area = area, scale = scale)
           } else if (endpoint == "report") {
             fips_codes <- area
           }
           ejamit(fips = fips_codes, radius = buffer)
         },
         stop("Invalid method specified.") # Handle unrecognized methods.
  )
}

#* Return EJAM analysis data as JSON
#* @param sites A data frame of site coordinates (lat/lon)
#* @param shape A GeoJSON string representing the area of interest
#* @param fips A FIPS code for a specific US Census geography
#* @param buffer The buffer radius in miles
#* @param geometries A boolean to indicate whether to include geometries in the output
#* @param scale The Census geography at which to return results (blockgroup or county)
#* @post /data
function(sites = NULL, shape = NULL, fips = NULL, buffer = 0, geometries = FALSE, scale = NULL, res) {
  # Determine the input method.
  method <- if (!is.null(sites)) "latlon" else if (!is.null(shape)) "SHP" else if (!is.null(fips)) "FIPS" else NULL
  area <- sites %||% shape %||% fips
  
  if (is.null(method) || is.null(area)) {
    res$status <- 400
    return(handle_error("You must provide valid points, a shape, or a FIPS code."))
  }
  
  # Perform the EJAM analysis.
  result <- tryCatch(
    ejamit_interface(area = area, method = method, buffer = as.numeric(buffer), scale = scale, endpoint = "data"),
    error = function(e) {
      res$status <- 400
      handle_error(e$message)
    }
  )
  
  # If an error was returned from the interface, return it.
  if ("error" %in% names(result)) {
    return(result)
  }
  
  # Prepare the final JSON output.
  if (geometries) {
    output_shape <- switch(method,
                           "latlon" = sf::st_as_sf(sites, coords = c("lon", "lat"), crs = 4326),
                           "SHP" = geojson_sf(shape),
                           "FIPS" = shapes_from_fips(fips)
    )
    # Combine the analysis results with the geographic shapes.
    return(cbind(data.table::setDF(result$results_bysite), output_shape))
  } else {
    return(result$results_bysite)
  }
}


shapefile_addcols <- function(shp, addthese = c('fipstype', 'pop', 'NAME', 'STATE_ABBR', 'STATE_NAME', 'SQMI', 'POP_SQMI'),
                              fipscolname = "FIPS", popcolname = "pop", overwrite = FALSE) {
  if (!overwrite) {
    addthese <- setdiff(addthese, colnames(shp))
  }

  # figure out the FIPS column, get it as a vector
  if (fipscolname %in% colnames(shp)) {
    fipsvector <- as.vector(sf::st_drop_geometry(shp)[, fipscolname]) # fipscolname was found
  } else {
    if ("fips" %in% fipscolname) {
      fipsvector <- as.vector(sf::st_drop_geometry(shp)[, 'fips']) # use "fips" lowercase since cant find fipscolname
    } else {
      if ("fips" %in% EJAM:::fixnames_aliases(colnames(shp))) {  # use 1st column that is an alias for fips
        warning(fipscolname, "is not a column name in shp, so using a column that seems to be an alias for FIPS")
        fipsvector <- as.vector(sf::st_drop_geometry(shp)[, which(fixnames_aliases(colnames(shp)) == "fips")[1]])
      } else {
        warning("cannnot find a column that can be identified as the FIPS, so using NA for columns like STATE_ABBR or STATE_NAME")
        fipsvector <- rep(NA, nrow(shp)) # NA for all rows
      }
    }
  }

  ftype <- EJAM:::fipstype(fipsvector)

  if ('fipstype' %in% addthese) {
    shp$fipstype <- EJAM:::fipstype(fipsvector) # NA if fips is NA
  }

  if ('NAME' %in% addthese) {
    shp$NAME <- EJAM:::fips2name(fipsvector) # NA if fips is NA
    
  }

  if ('STATE_ABBR' %in% addthese) {
    shp$STATE_ABBR <- EJAM:::fips2state_abbrev(fipsvector) # NA if fips is NA
    
  }

  if ('STATE_NAME' %in% addthese) {
    shp$STATE_NAME <- EJAM:::fips2statename(fipsvector) # NA if fips is NA
    
  }

  if ('pop' %in% addthese) {
    shp$pop <- EJAM:::fips2pop(fipsvector) # NA for city type
    
  }

  if ('SQMI' %in% addthese) {
    areas <- rep(NA, length(fipsvector))
    made_of_bgs <- EJAM:::fipstype(fipsvector) %in% c("state", "county", "tract", "blockgroup") # not block, not city - for blocks, see  ?tigris::block_groups()

    myfunction = function(f1) {
      sum( blockgroupstats[blockgroupstats$bgfips %in% EJAM:::fips_bgs_in_fips1(f1), arealand], na.rm = TRUE)
    }
    areas_sqmeters <- sapply(fipsvector[made_of_bgs], FUN = myfunction)

    areas_sqmi <- EJAM:::convert_units(areas_sqmeters, from = "sqmeter", towhat = "sqmi")
    
    shp$SQMI<-areas_sqmi
    #shp$SQMI <- EJAM:::area_sqmi_from_fips(fipsvector, download_city_fips_bounds = FALSE, download_noncity_fips_bounds = FALSE)
    #shp$SQMI[ftype %in% "city" & !is.na(ftype)] <- EJAM:::area_sqmi_from_shp(shp[ftype %in% "city" & !is.na(ftype), ]) # *** check the numbers
    shp$SQMI <- round(shp$SQMI, 2)
  }

  if ('POP_SQMI' %in% addthese) {
    if ('SQMI' %in% colnames(shp)) {
      sqmi = shp$SQMI
    } else {
      sqmi = EJAM:::area_sqmi_from_shp(shp)
    }
    if (popcolname %in% colnames(shp)) {
      pop = as.vector(sf::st_drop_geometry(shp)[, popcolname])
      shp$POP_SQMI <- ifelse(sqmi == 0, NA, pop / sqmi)
      shp$POP_SQMI <- round(shp$POP_SQMI, 2)
    } else {
      warning("Cannot find a column that can be identified as the population, so using NA for POP_SQMI")
      shp$POP_SQMI <- NA
    }
  }

  return(shp)
}

#* Generate an EJAM report in HTML format
#* @param lat Latitude of the site
#* @param lon Longitude of the site
#* @param shape A GeoJSON string representing the area of interest
#* @param fips A FIPS code for a specific US Census geography
#* @param buffer The buffer radius in miles
#* @get /report
#* @serializer html
function(lat = NULL, lon = NULL, shape = NULL, fips = NULL, buffer = 3, res) {
  # Determine the input method and prepare the area.
  method <- if (!is.null(lat) && !is.null(lon)) "latlon" else if (!is.null(shape)) "SHP" else if (!is.null(fips)) "FIPS" else NULL
  area <- if (method == "latlon") data.frame(lat = as.numeric(lat), lon = as.numeric(lon)) else shape %||% fips

  if (is.null(method) || is.null(area)) {
    res$status <- 400
    return(handle_error("You must provide valid coordinates, a shape, or a FIPS code.", "html"))
  }
  
  # Perform the EJAM analysis.
  result <- tryCatch(
    ejamit_interface(area = area, method = method, buffer = as.numeric(buffer), endpoint="report"),
    error = function(e) {
      res$status <- 400
      handle_error(e$message, "html")
    }
  )

  # If an error occurred during the analysis, return the error message.
  if (is.character(result)) {
    return(result)
  }

  # Prepare report.
  to_map<-NULL # Clear any previous maps

  if (method=="FIPS"){
    # In the case of states and counties we need special handling
    # Do this based on character count of FIPS
    # Note we are not validating FIPS :(
    if (nchar(area)==2){
      # State
      fips<-area
      shp <- states_shapefile[match(fips, states_shapefile$GEOID), ]
      shp$FIPS <- shp$GEOID

      shp <- EJAM:::shapefile_dropcols(shp)
      shp <- shapefile_addcols(shp) # Use shapefile_addcols() above
      shp <- EJAM:::shapefile_sortcols(shp)

      to_map<-shp
    }
    if (nchar(area)==5){
      # County
      fips<-area
      request_start<-'https://services.arcgis.com/P3ePLMYs2RVChkJx/ArcGIS/rest/services/USA_Boundaries_2022/FeatureServer/2/query?where=FIPS%3D%27'
      request_end<-'%27&outFields=NAME%2CFIPS%2CSTATE_ABBR%2CSTATE_NAME&returnGeometry=true&f=geojson'
      request<-paste0(request_start, fips, request_end)
      shp <- sf::st_read(request) # data.frame not tibble

      shp <- shp[match(fips, shp$FIPS), ]
      shp$FIPS <- fips # now include the original fips in output even for rows that came back NA / empty polygon

      shp<-EJAM:::shapefile_dropcols(shp)
      shp<-shapefile_addcols(shp) # Use shapefile_addcols() above
      shp<-EJAM:::shapefile_sortcols(shp)

      to_map<-shp
    }
  }

  # Get submitted polygon shape to appear in report map.
  if (method == "SHP"){
    to_map<-geojson_sf(area) # TBD: get this returned from ejamit_interface
    to_map$ejam_uniq_id <- 1 # Might run into issues here for multisite reports
  }

  # Generate and return the HTML report.
  ejam2report(result, sitenumber = 1, return_html = TRUE, launch_browser = FALSE, submitted_upload_method = method, shp=to_map,
    report_title="EJSCREEN Community Report")
  

}

#* Serve static assets from the ./assets directory
#* @assets ./assets /
list()