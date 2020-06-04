test: htmlproofer

htmlproofer: public
	docker run -it --rm -v "$$(pwd)/public:/src" \
		chabad360/htmlproofer \
		htmlproofer /src --check-img-http --check-sri --check-html

public:
	hugo

.PHONY: clean
clean:
	rm -rf public
