# Written with assistance from Google Gemini

# Use Ubuntu 22.04 (Jammy Jellyfish) as the base image
# This is an LTS release with a mature and complete CRAN binary repository
FROM ubuntu:22.04

# Set DEBIAN_FRONTEND to noninteractive to avoid prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Update apt cache and install user-requested libraries + R dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # --- R dependencies ---
    software-properties-common \
    wget \
    gnupg \
    ca-certificates \
    locales \
    # --- EJAM-required libraries ---
    libudunits2-dev \
    libmysqlclient-dev \
    libcurl4-openssl-dev \
    libsodium-dev \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    libssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libjq-dev \
    libprotobuf-dev \
    protobuf-compiler \
    cmake \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libwebp-dev \
    libharfbuzz-dev \
    libfribidi-dev && \
    # Clean up apt cache
    rm -rf /var/lib/apt/lists/*

# Configure locale to support UTF-8
RUN locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Add the CRAN repository for R 4.x
RUN wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc && \
    # Add the R 4.0+ repository for Ubuntu 22.04 (Jammy)
    add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu jammy-cran40/"

# Update apt cache again to include the new CRAN repository
# Then install the specific R 4.5 version AND some memory-intensive dependencies
RUN apt-get update && \
    apt-get install -y \
    # --- R Base ---
    r-base=4.5.* \
    r-base-dev=4.5.* \
    # --- Pre-compiled R packages in this repo ---
    r-cran-sf \
    r-cran-data.table \
    r-cran-rcpp \
    r-cran-cpp11 \
    r-cran-remotes \
    r-cran-plumber \
    r-cran-shiny \
    r-cran-testthat \
    r-cran-jsonlite \
    r-cran-rlang \
    r-cran-r6 \
    r-cran-promises \
    r-cran-httpuv \
    && \
    # Clean up apt cache
    rm -rf /var/lib/apt/lists/*

# Download 'EJAM' and install its remaining dependencies from binary repos
RUN \
    # Get EJAM R package (v2.32.6.003)
    wget -c https://github.com/ejanalysis/EJAM/archive/refs/tags/v2.32.6.003.tar.gz -O - | tar -xz && \
    \
    # Install remaining dependencies from RStudio's binary repo
    # This includes packages like 'shinytest2' and 'webshot' that were not in apt
    # Then, install EJAM itself.
    # We use MAKEFLAGS="-j1" to force single-core compilation, saving memory.
    MAKEFLAGS="-j1" R -e " \
        install.packages(c('shinytest2', 'webshot'), repos=c('https://packagemanager.rstudio.com/all/__linux__/jammy/latest')); \
        remotes::install_local('/EJAM-2.32.6.003', dependencies=TRUE, upgrade='always', build=FALSE, repos=c('https://packagemanager.rstudio.com/all/__linux__/jammy/latest'), INSTALL_opts=c('--preclean', '--no-multiarch', '--with-keep.source')) \
    " && \
    \
    # Clean up the downloaded source directory
    rm -rf /EJAM-2.32.6.003

# Set the environment back to default
ENV DEBIAN_FRONTEND=dialog

# Copy into the container
COPY / /

# Open port 8080 to traffic
EXPOSE 8080

# When the container starts, start the main.R script
ENTRYPOINT ["Rscript", "main.r"]