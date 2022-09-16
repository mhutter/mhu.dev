DOCKER ?= podman

test: htmlproofer

.PHONY: htmlproofer
htmlproofer: public
	$(DOCKER) run -it --rm -v "$$(pwd)/public:/src" \
		docker.io/chabad360/htmlproofer \
		htmlproofer /src \
		--check-sri=true \
		--ignore-status-codes=999

.PHONY: public
public:
	hugo

.PHONY: clean
clean:
	rm -rf public
