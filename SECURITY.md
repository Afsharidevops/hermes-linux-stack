# Security notes

## Network defaults

The OmniRoute dashboard (`20128`), OmniRoute API (`20129`), Hermes (`8642`/`9119`), Open WebUI (`3000`), and n8n (`5678`) bind to `127.0.0.1` by default. Caddy is the component intended to bind public HTTP/HTTPS ports.

The OmniRoute API is intentionally separate from the dashboard port in this stack. Internal clients use `http://omniroute:20129/v1` over the private Compose network.

## OmniRoute API authentication

Fresh installs default to `OMNIROUTE_REQUIRE_API_KEY=false` so OmniRoute can be configured before an endpoint key exists. This is acceptable only while the API host binding stays loopback or otherwise protected.

After adding an endpoint API key in OmniRoute, run:

```bash
./manage.sh enable-omniroute-api-auth
```

The command stores the key for Hermes and Open WebUI and enables OmniRoute API-key enforcement. If the OmniRoute API is bound to a LAN/public address, enable API-key enforcement first.

## Secrets

Never commit `.env`, `data/hermes/.env`, OmniRoute data, execution secrets, private SSH keys, n8n credentials, or Caddy state. Back up the generated OmniRoute secrets and `data/omniroute` together. Keep `MACHINE_ID_SALT` unique per deployment; the installer also generates `OMNIROUTE_WS_BRIDGE_SECRET` for production WebSocket bridge authentication.

## Execution isolation

The existing stack execution broker/plugin design remains in Compose. Execution profiles are disabled by default and should not be enabled until their approval/signing/SSH material is configured correctly.
