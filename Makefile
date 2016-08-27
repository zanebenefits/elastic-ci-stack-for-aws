.PHONY: all build clean setup upload create-stack update-stack validate toc

BUILDKITE_STACK_BUCKET ?= buildkite-aws-stack
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
STACK_NAME ?= buildkite
SHELL=/bin/bash -o pipefail

all: setup build

build: build/aws-stack.json

.DELETE_ON_ERROR:
build/aws-stack.json: $(wildcard templates/*.yml) templates/mappings.yml
	-mkdir -p build/
	bundle exec cfoo $^ > $@

clean:
	-rm -f build/*

setup:
	bundle check || ((which bundle || gem install bundler --no-ri --no-rdoc) && bundle install --path vendor/bundle)

templates/mappings.yml:
	( cat templates/mappings.yml.header && curl -s https://coreos.com/dist/aws/aws-stable.json | ruby -r json -e 'JSON.parse(ARGF.read).each { |region, images| puts "    #{region}:\n      AMI: #{images["hvm"]}" unless region == "release_info" }' ) > templates/mappings.yml

upload: build/aws-stack.json
	aws s3 sync --acl public-read build s3://$(BUILDKITE_STACK_BUCKET)/

config.json:
	test -s config.json || $(error Please create a config.json file)

extra_tags.json:
	echo "{}" > extra_tags.json

create-stack: config.json build/aws-stack.json extra_tags.json
	aws cloudformation create-stack \
	--output text \
	--stack-name $(STACK_NAME) \
	--disable-rollback \
	--template-body "file://$(PWD)/build/aws-stack.json" \
	--capabilities CAPABILITY_IAM \
	--parameters "$$(cat config.json)" \
	--tags "$$(cat extra_tags.json)"

update-stack: config.json templates/mappings.yml build/aws-stack.json
	aws cloudformation update-stack \
	--output text \
	--stack-name $(STACK_NAME) \
	--template-body "file://$(PWD)/build/aws-stack.json" \
	--capabilities CAPABILITY_IAM \
	--parameters "$$(cat config.json)"

validate: build/aws-stack.json
	aws cloudformation validate-template \
	--output table \
	--template-body "file://$(PWD)/build/aws-stack.json"

toc:
	docker run -it --rm -v "$$(pwd):/app" node:slim bash -c "npm install -g markdown-toc && cd /app && markdown-toc -i Readme.md"
