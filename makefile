exec:
	docker compose start
	docker compose exec app bash

stop:
	docker compose stop

diff:
	git diff --cached > .diff

reinstall:
	-nimble uninstall nicp_cdk -iy
	nimble install -y

run:
	-nimble uninstall nicp_cdk -iy
	nimble install -y
	ndfx cHeaders
	dfx killall
	rm -rf /application/examples/*/.dfx
	rm -rf /application/examples/*/*/.dfx
	dfx start --clean --background --host 0.0.0.0:4943 --domain localhost --domain 0.0.0.0
