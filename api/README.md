# eastsidecal-submit

Azure Functions (v4, Node.js 20, Flex Consumption, Linux) behind the camera
button on card photos and the /suggest/ form.

- POST /api/photo: multipart (photo, page, card_id, card_name, credit) or
  JSON with photo as base64. JPEG, PNG, WebP, or HEIC by magic bytes, 8 MB max.
  Saves pending/photos/{date}/{uuid}.{ext} and {uuid}.json.
- POST /api/suggest: kind (event, place, partner, other), name, date, time,
  place, link, blurb, contact_email, optional town (city id, partner spots),
  optional photo. Saves pending/suggestions/{date}/{uuid}.json (and the photo).
  For kind=partner, when PARTNER_WEBHOOK_URL is set, POSTs the saved record
  (plus offering and a read-only photo SAS when a photo was saved) to that URL
  after the blob write. Webhook failures are logged and do not fail the
  browser response.
- Both: CORS to eastsidecalendar.com (+ localhost), honeypot field
  `website`, 10 posts per hashed IP per hour (ratelimit/ blobs, deleted
  after a day by a lifecycle rule). The raw IP is never stored.

App settings (not in the repo): SUBMIT_STORAGE (connection string), IP_SALT.
Optional: ALLOWED_ORIGINS, RATE_LIMIT, PARTNER_WEBHOOK_URL,
PARTNER_WEBHOOK_KEY.

When PARTNER_WEBHOOK_KEY is set, the partner webhook sends
`Authorization: Bearer <key>`.

Deploy: `npm install`, zip the folder, then
`az functionapp deployment source config-zip -n eastsidecal-submit -g Default-Web-NorthCentralUS --src api.zip`.
