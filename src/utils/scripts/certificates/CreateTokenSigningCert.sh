openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout IdentityServer.key -out IdentityServer.crt -subj "//CN=audacia" -days 3650