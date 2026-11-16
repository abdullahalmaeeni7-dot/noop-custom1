# Gemini nutrition service

This service runs independently of the WHOOP account bridge. No WHOOP developer account, OAuth setup or database is needed for nutrition AI. Your food log continues to use protected storage on your iPhone.

## Deploy from GitHub

1. Open [Deploy on Render](https://render.com/deploy?repo=https://github.com/abdullahalmaeeni7-dot/noop-custom1) and connect the repository. The included `render.yaml` defines the Docker service. Review the host's current plan terms before creating it.
2. Enter a **replacement Gemini key** in Render's private `AI_API_KEY` environment setting. The supplied Blueprint selects `AI_PROVIDER=gemini`, `AI_MODEL=gemini-2.5-flash`, and `AI_API_URL=https://generativelanguage.googleapis.com/v1beta`. A key shared in a chat should be revoked. Never put the replacement in GitHub, an IPA, a screenshot, or an app text field.
3. Deploy and wait for the service to report healthy. Copy its HTTPS origin, for example `https://your-service.onrender.com` (no path or query).
4. Open the service's Environment page and copy the automatically generated **`NUTRITION_ACCESS_TOKEN`**. This is your private service access code, separate from the Gemini key.
5. In the iPhone app, open **Nutrition → Settings → Connect Nutrition Service**. Enter the HTTPS origin and server access code, then connect. The code is saved in the iPhone's non-synchronizing Keychain. The provider key stays on the server.
6. Try **Add Food → AI text**, review the returned portions/macros, then save. For a photo, choose **AI photo → Take Photo** or **Library**, then **Analyze Photo**. Taking a photo and manually logging food also work without a server.

The service has not been deployed automatically. A running host, a valid Gemini key with access to the chosen model, and successful app pairing are required for real AI results. A free hosting service may sleep; allow it to wake before retrying a timed-out connection.

## Run on your own server

Install Node 24.5 or later and run `npm ci` at the repository root. Copy `Server/.env.example` to an untracked `Server/.env`. Set `AI_API_KEY` and generate `NUTRITION_ACCESS_TOKEN` with `node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))"`.

Start from the repository root:

```bash
node --env-file=Server/.env Server/nutrition-server.mjs
```

Put the listener behind HTTPS before pairing the phone. Its default listener is `127.0.0.1:8787`; the Docker image listens on `0.0.0.0:8787` for the hosting proxy. Keep the access code private. To revoke access, replace that code in the host environment, redeploy, and pair the app again. Disconnecting on the phone deletes only its local Keychain code.

## Contracts and limits

`GET /health` exposes readiness only. `GET /session` validates the service bearer code. All four `/api/nutrition/*` POST routes require that code. Inputs and outputs are validated with zod. Invalid provider JSON gets one retry; rate-limit/auth errors do not. Photos must be JPEG/PNG below 1 MB after on-device compression. Provider response bodies and credentials are never included in app-facing errors. English/Arabic response selection uses `language: "en" | "ar"` and preserves numeric JSON keys.

This is a private single-user service. It accepts up to eight AI requests per minute per directly connected address; a reverse proxy may share that bucket among your devices. No food/image database is created. Existing WHOOP OAuth bridge setup remains in [README.md](README.md); it is optional for this nutrition-only service.
