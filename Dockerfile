FROM rocker/geospatial:4.6.1

WORKDIR /srv/sampamaisrural
COPY . /srv/sampamaisrural
RUN R -q -e "install.packages('renv', repos='https://cloud.r-project.org'); renv::restore(prompt=FALSE)" \
    && R CMD INSTALL .

EXPOSE 3838
CMD ["R", "-q", "-e", "sampamaisrural::run_app(host='0.0.0.0', port=3838, launch.browser=FALSE)"]
