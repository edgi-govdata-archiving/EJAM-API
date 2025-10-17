# Based on https://github.com/petegordon/RCloudRun
# start from the rocker/r-ver:4.1 image
FROM rocker/r-ver:4.1

ENV DEBIAN_FRONTEND="noninteractive" TZ="America/Chicago"

## Install (non-R) packages
RUN apt-get -y update && TZ=America/Chicago DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libfontconfig1-dev \
    libudunits2-dev \
    libcairo2-dev \
    libcurl4-openssl-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    libjq-dev \
    libprotobuf-dev \
    pandoc \
    protobuf-compiler \
    software-properties-common \
    wget
RUN apt-get update

## Install R packages "plumber" (helps create APIs)
##  and "remotes" (helps install EJAM)
RUN R -e "install.packages(c('remotes', 'plumber'), repos=c('https://packagemanager.rstudio.com/all/__linux__/focal/latest'))"

## Get EJAM R package (e.g., v2.32.6)
## see https://github.com/ejanalysis/EJAM/releases/latest
RUN wget -c https://github.com/ejanalysis/EJAM/archive/refs/tags/v2.32.6.001.tar.gz -O - | tar -xz

## Install EJAM R package (e.g., v2.32.6)
RUN R -e "remotes::install_local('/EJAM-2.32.6.001', upgrade='always', build=FALSE, dependencies=TRUE, repos=c('https://packagemanager.rstudio.com/all/__linux__/focal/latest', 'https://mirror.csclub.uwaterloo.ca/CRAN/'), INSTALL_opts=c('--preclean', '--no-multiarch', '--with-keep.source'))" 

# Copy into the container
COPY / /

# Open port 8080 to traffic
EXPOSE 8080

# When the container starts, start the main.R script
ENTRYPOINT ["Rscript", "main.r"]