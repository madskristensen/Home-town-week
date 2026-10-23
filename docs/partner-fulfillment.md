# Partner fulfillment (bot)

Internal pipeline for paid partner spots. Not marketing copy.

## Flow

1. Sponsor pays via a Stripe Payment Link on `/partner/`.
2. Stripe redirects to `/partner/thanks/?offering=<slug>`.
3. Sponsor submits name, website, blurb, email, optional photo, and (when needed) city.
4. The thanks form POSTs to Azure Function `/api/suggest` with `kind=partner`.
   The offering slug is stored in field `place`. City id is field `town`.
5. The function writes `pending/suggestions/{date}/{uuid}.json` (and the photo
   blob when present) in the `submissions` container.
6. If `PARTNER_WEBHOOK_URL` is set on `eastsidecal-submit`, the function POSTs
   the saved record to that URL (fire-and-forget). Optional
   `PARTNER_WEBHOOK_KEY` becomes `Authorization: Bearer <key>`.
   Photo: `photo_sas` / `photo_url` (read-only SAS, about 7 days), or
   `photo_blob` path, or `photo_base64` when under about 1.5 MB and SAS fails.
7. The bot merges creative into `_data/sponsors.yml` (or the birthday row when
   that is the offering), commits, and pushes `main` (GitHub Pages).
8. After the spot is live on eastsidecalendar.com, email the sponsor from
   `post@` with a short confirmation and the page link. Notify Mads.

Do not publish from the submission alone without a sanity check (HTTPS link,
no kids' faces in the photo, no em dashes in copy). Prefer
`script/apply-sponsor.py` for sponsors.yml merges; hand-edit YAML when needed.

## Offering → data mapping

| Offering slug | Where it lands |
| --- | --- |
| `featured-weekend` | `cards.weekend[]` card (`title`, `href`, `blurb`, `image`, `town` defaults to Sponsored, `sponsored: true`) |
| `featured-city` | `cards.cities.<town>[]` same card shape; `town` form field is the city id |
| `birthday-featured` | `_data/birthday_venues.yml` row with `sponsored: true` (not sponsors.yml); needs city id in `town` |
| `seasonal-christmas` | `seasons.christmas` line (`name`, `url`) and/or `seasons.christmas.cards[]` |
| `seasonal-fall` | `seasons.fall` line and/or `seasons.fall.cards[]` |
| `seasonal-spring-break` | `seasons.spring-break` line and/or `seasons.spring-break.cards[]` |
| `seasonal-summer-camps` | `seasons.summer-camps` line (`name`, `url`) on `/summer-camps/` |
| `email-one` | `email` (`name`, `url`, `line`) for one Thursday issue |
| `email-four` | same `email` block, kept for four issues |
| `camp-enhanced` | `listings[]` enhanced camp row (`name`, `url`, `town` city id, `blurb`, photo fields) |

Card shape used by weekend, city, and seasonal cards: `title`, `href` (https),
`blurb`, `image`, `town` (defaults to "Sponsored"), `sponsored: true`. Plugins
sanitize cards and listings in `_plugins/summer_camps.rb`.

## Env on eastsidecal-submit

- `PARTNER_WEBHOOK_URL` (optional): HTTPS endpoint that receives partner JSON.
- `PARTNER_WEBHOOK_KEY` (optional): sent as `Authorization: Bearer <key>`.

Redeploy the Function app after pulling these code changes (see `api/README.md`).
