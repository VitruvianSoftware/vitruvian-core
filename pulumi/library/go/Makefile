.PHONY: all build test lint tidy clean

all: tidy lint build test

build:
	go build ./...

test:
	go test -v ./...

lint:
	go fmt ./...
	go vet ./...

tidy:
	go mod tidy

clean:
	rm -rf dist/
