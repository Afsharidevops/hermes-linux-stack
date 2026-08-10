# Smart Router public ingress — optional Caddy and external reverse proxy

Branch: `main`  
Backend: **9router**

Public access is optional. Internal stack clients continue to use the Docker-network URL:

```text
http://smart-router:8080/v1
```

External OpenAI-compatible applications can use a public URL such as:

```text
https://api.example.com/v1
```

There are two supported deployment patterns. Choose **one** for public ingress.

---

## Mode A — stack Caddy owns HTTPS

Use this when the stack VM itself is the Internet-facing reverse proxy.

```text
Internet client
      |
      | HTTPS :443
      v
Stack VM / Caddy
      |
      | Docker network HTTP
      v
Smart Router :8080
      |
      v
9router
```

### 1. DNS

Point the public records directly to the stack VM public IP, for example:

```text
api.example.com  -> STACK_PUBLIC_IP
chat.example.com -> STACK_PUBLIC_IP        # optional Open WebUI
```

### 2. Caddyfile

Use:

```text
examples/caddy/Caddyfile.smart-router-standalone-tls.example
```

Copy it into the runtime location used by the stack:

```bash
mkdir -p data/caddy
cp examples/caddy/Caddyfile.smart-router-standalone-tls.example data/caddy/Caddyfile
```

Edit the example domains before startup.

### 3. Start Caddy

Enable the existing `caddy` profile with the rest of the services you need. Caddy listens on ports 80/443 and obtains/manages certificates automatically for qualifying public domain names.

Only expose services you intentionally want public. The Smart Router API route is the important one for external API clients. Administrative dashboards should normally remain private/VPN-only.

---

## Mode B — separate reverse-proxy VM owns HTTPS

Use this when you have a dedicated edge VM for TLS and domains, while the Hermes stack runs on another VM.

Recommended topology:

```text
Internet client
      |
      | HTTPS :443
      v
Reverse-proxy VM
  TLS certificate
      |
      | private HTTP :8088
      v
Stack VM / Caddy HTTP-only
      |
      | Docker network HTTP
      v
Smart Router :8080
      |
      v
9router
```

Example addresses used below:

```text
Reverse-proxy VM private IP: 10.20.0.10
Stack VM private IP:         10.20.0.20
Stack Caddy private port:    8088
Public API domain:           api.example.com
```

Replace them with your real private addresses and domains.

### 1. DNS points to the reverse-proxy VM

```text
api.example.com -> EDGE_PUBLIC_IP
```

Do **not** point the public API DNS record directly to the stack VM in this mode.

### 2. Run an HTTP-only Caddy service on the stack VM

This package includes:

```text
examples/caddy/docker-compose.external-proxy.yml
examples/caddy/Caddyfile.smart-router-external-proxy-http.example
```

Install the HTTP-only Caddyfile:

```bash
mkdir -p data/caddy
cp examples/caddy/Caddyfile.smart-router-external-proxy-http.example data/caddy/Caddyfile
```

Edit these values in the Caddyfile:

```text
api.example.com
10.20.0.10/32     # edge proxy private address/CIDR
```

Then start the extra HTTP-only service with the stack's normal Compose file plus the optional Compose file:

```bash
CADDY_HTTP_BIND_IP=10.20.0.20 \
CADDY_HTTP_PORT=8088 \
docker compose \
  -f docker-compose.yml \
  -f examples/caddy/docker-compose.external-proxy.yml \
  --profile caddy-http \
  up -d caddy-http
```

The Caddyfile site addresses explicitly begin with `http://`. That keeps this inner Caddy listener HTTP-only; it does not request certificates or redirect to HTTPS.

Do **not** also enable the normal `caddy` profile for the same ingress unless you intentionally want both listeners.

### 3. Restrict the stack VM firewall

The private Caddy listener should accept connections only from the reverse-proxy VM.

Conceptually:

```text
ALLOW tcp/8088 FROM 10.20.0.10
DENY  tcp/8088 FROM everything else
```

Use your platform firewall (nftables, firewalld, ufw, cloud security group, etc.) to enforce this. Binding `CADDY_HTTP_BIND_IP` to the stack VM's private address is an additional boundary; it does not replace firewalling.

Plain HTTP between VMs is appropriate only on a trusted private network. If the link crosses an untrusted network, use WireGuard/Tailscale/private networking or TLS between the two proxies.

### 4. Configure the edge reverse proxy

Your edge proxy must:

- terminate HTTPS for `api.example.com`,
- forward to `http://10.20.0.20:8088`,
- preserve the original `Host`,
- provide standard forwarded client/protocol headers.

If the edge VM also uses Caddy, an example is included:

```text
examples/caddy/Caddyfile.edge-reverse-proxy.example
```

The essential rule is equivalent to:

```text
api.example.com -> http://10.20.0.20:8088
```

The inner stack Caddy example trusts only the configured edge proxy CIDR for forwarded client information. Do not configure a broad public CIDR as trusted.

### 5. Test both hops

From the reverse-proxy VM, first test the private origin while preserving the public Host header:

```bash
curl -i http://10.20.0.20:8088/health \
  -H 'Host: api.example.com'
```

Then test from an external machine through TLS:

```bash
curl -i https://api.example.com/health
```

And finally test the authenticated OpenAI-compatible API:

```bash
curl https://api.example.com/v1/models \
  -H 'Authorization: Bearer YOUR_CLIENT_KEY'
```

---

## Domain layout

A clean optional layout is:

```text
api.example.com       -> Smart Router API
chat.example.com      -> Open WebUI, if public access is desired
```

Keep administrative services such as the 9router dashboard, Hermes dashboard, and n8n editor private unless you have a separate authentication/access-control layer in front of them.

---

## Which mode should I use?

Use **Mode A** when the stack VM can safely receive ports 80/443 and you want the fewest moving parts.

Use **Mode B** when you already centralize DNS/TLS on another VM, want one certificate/edge layer for many applications, or do not want the stack VM directly exposed to the Internet.

Both modes keep Smart Router and the downstream routing backend architecture unchanged.
