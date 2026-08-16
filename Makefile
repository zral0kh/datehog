# datehog test and deploy
#
#   make tests                run the test suite (unit + both differentials)
#   make deploy VERSION=vX.Y.Z   test, tag and release on origin, stage the
#                                 packages/preview copy, push it to the packages
#                                 fork, and print the upstream PR link
#   make setup                 create the venv the differential tests need
#
# `deploy` refuses a VERSION that isn't strictly greater than the last one
# published on GitHub (typst.toml may already have been bumped by hand ahead
# of a release). See scripts/release.sh for the full pipeline; it is not
# meant to be run by hand.

SHELL := /bin/bash

PY := $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)

.PHONY: tests deploy setup

tests:
	PY=$(PY) ./tests/run.sh --all

deploy:
	@test -n "$(VERSION)" || { echo "usage: make deploy VERSION=vX.Y.Z"; exit 1; }
	./scripts/release.sh "$(VERSION)"

setup: .venv/bin/python

.venv/bin/python:
	uv venv .venv
	VIRTUAL_ENV=.venv uv pip install -r requirements.txt