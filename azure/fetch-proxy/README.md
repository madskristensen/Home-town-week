# fetch-proxy

Azure Function (Flex Consumption, Node 20) `eastsidecal-fetch` in RG Default-Web-NorthCentralUS.

`GET /api/fetch?url=<encoded https url>` with header `x-functions-key`. Only hosts in app setting
`ALLOWED_HOSTS` (comma-separated, exact) are fetched; redirects followed only within the allowlist.
Returns upstream status, Content-Type and raw body. 10s timeout, 5 MB cap.

Deploy: `npm install --omit=dev && func azure functionapp publish eastsidecal-fetch` or zip deploy:
`zip -r ../fp.zip . && az functionapp deployment source config-zip -g Default-Web-NorthCentralUS -n eastsidecal-fetch --src ../fp.zip`
