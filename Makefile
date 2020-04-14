SHELL := /bin/bash
.PHONY: $(MAKECMDGOALS)
.EXPORT_ALL_VARIABLES:
.DEFAULT_GOAL := default
FLASK_ENV ?= development
ML_PORT ?= 3000
MONGODB_HOST ?= localhost
MONGODB_PORT ?= 27117
MONGODB_DBNAME ?= efrs_tmp_db
COMPOSE_PROJECT_NAME ?= frs-core
API_KEY ?= test-api-key
SKIP_TESTS ?= true
FORCE_FAIL_UNIT_TESTS ?= false
FORCE_FAIL_E2E_TESTS ?= false

#####################################
##### MAIN TESTS
#####################################

# Run main tests, with faster tests run first
default: test/unit test/lint test

# Run main tests
test: MEM_LIMIT = 4g
test: SKIP_TESTS = false
test: FLASK_ENV = production
test:
	docker-compose up --build --abort-on-container-exit

#####################################
##### RUNNING IN DOCKER
#####################################

# Build app's container
build:
	docker-compose build ml

# Run built app's container
up:
	docker-compose up ml

# Stop running containers
down:
	docker-compose down

# Stop all running containers
down/all:
	docker stop $$(docker ps -a -q)

#####################################
##### RUNNING IN LOCAL ENVIRONMENT
#####################################

# Install dependencies and prepare environment
setup:
	chmod +x ci-test.sh ml/run.sh e2e/run-e2e-test.sh tools/crash-lab.sh
	python -m pip install -r ml/requirements.txt
	imageio_download_bin freeimage
	python -m pip install -e ml/srcext/insightface/python-package

# Run application
start: db
	ml/run.sh start

# Stop application
stop:
	ml/run.sh stop

#####################################
##### TESTING IN LOCAL ENVIRONMENT
#####################################

# Run local tests
test/local: test/unit test/lint test/i9n

# Run unit tests
test/unit:
	python -m pytest -m "not integration" ml/src

# Run lint checks
test/lint:
	python -m pylama --options ml/pylama.ini ml/src

# Run integration tests
test/i9n:
	python -m pytest -m integration $(CURDIR)/ml/src

# Run E2E tests (also starts db and application automatically)
test/e2e: e2e/local

#####################################
##### E2E TESTING
#####################################

# Runs E2E tests against an already running application
e2e:
	e2e/run-e2e-test.sh

# Runs E2E and also checks if given host is able to handle scanning all images
e2e/extended: scan e2e

# Runs E2E after automatically starting db and application automatically
e2e/local: start
	timeout 10s bash -c "until [ -f $(CURDIR)/ml/$(COMPOSE_PROJECT_NAME).pid ]; do sleep 1; done"
	sleep 5s
	test -f $(CURDIR)/ml/$(COMPOSE_PROJECT_NAME).pid
	$(MAKE) e2e && ml/run.sh stop || (ml/run.sh stop; exit 1)

#####################################
##### DEV SCRIPTS
#####################################

# Detects faces on given images, with selected scanners, and output the results
demo: IMG_NAMES=015_6.jpg
demo: scan
scan:
	python -m ml.src.services.facescan.run

# Optimizes face detection parameters with a given annotated image dataset
optimize:
	python -m ml.src.services.facescan.optimizer.run

# Runs experiments whether the system will crash with given images, selected face detection scanners, RAM limits, image processing settings, etc.:
crash:
	tools/crash-lab.sh $(CURDIR)/ml/sample_images

#####################################
##### MISC
#####################################

# Gives a random project name
COMPOSE_PROJECT_NAME:
	@echo frs-core-$(ML_PORT)-$$(</dev/urandom tr -dc 'a-z0-9' | fold -w 1 | head -n 1)

# Finds an open port
PORT:
	@echo $$(while true; do port=$$(( RANDOM % 30000 + 30000 )); echo -ne "\035" | telnet 127.0.0.1 \
		$$port > /dev/null 2>&1; [ $$? -eq 1 ] && echo "$$port" && exit 0; done )

# Give a unique api_key
API_KEY:
	@echo tmp-$(COMPOSE_PROJECT_NAME)-$$(date +'%Y-%m-%d-%H-%M-%S-%3N')

# Give a unique mongodb dbname
MONGODB_DBNAME:
	@echo $(API_KEY)

# Starts a database container
db:
	@echo -ne "\035" | telnet 127.0.0.1 $(MONGODB_PORT) > /dev/null 2>&1; [ $$? -eq 1 ] && \
	docker-compose up -d mongodb && \
	echo "[Database up] SUCCESS! Started db on port $(MONGODB_PORT)" || \
	echo "[Database up] skipped, because port $(MONGODB_PORT) is taken"

# Shows code line stats
stats:
	(which tokei || conda install -y -c conda-forge tokei) && \
	tokei --exclude srcext/
