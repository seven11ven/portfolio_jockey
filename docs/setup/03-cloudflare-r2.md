# Setup 3: Cloudflare R2 file storage

Uploaded images, audio, video and documents are stored in a **private** Cloudflare R2 bucket. The bucket is never public. The app hands the browser short-lived links, each allowing one upload or one download.

**You'll need:** about 15 minutes, and Setups 1 and 2 finished.

> **Cost:** R2's free tier includes 10 GB of storage, and downloads are free. Cloudflare will probably ask for a payment method before you can create a bucket. The app refuses uploads past 9 GB (`STORAGE_QUOTA_BYTES`), so normal use stays free. Check Cloudflare's current pricing page if you're unsure.

## 1. Create the bucket
1. Sign in at [dash.cloudflare.com](https://dash.cloudflare.com) and open **R2 Object Storage**.
2. Click **Create bucket**.
   - **Name:** for example `portfolio-jockey`. Use lowercase letters, numbers and hyphens.
   - **Location:** Automatic is fine.
   - **Default storage class:** **Standard**. The free tier doesn't cover Infrequent Access.
3. After it's created, open the bucket's **Settings** and make sure **Public access** is **disabled**, with no public R2.dev URL and no custom domain.

## 2. Allow uploads from the app (CORS)
Browsers upload straight to R2, so the bucket must accept requests from the app's address.

1. In the bucket's **Settings**, find **CORS Policy** and click **Add CORS policy** or **Edit**.
2. Paste this, replacing `APP_URL` with the address you open the app at (the same one as in Setup 2):
   ```json
   [
     {
       "AllowedOrigins": ["APP_URL"],
       "AllowedMethods": ["PUT", "GET"],
       "AllowedHeaders": ["content-type"],
       "MaxAgeSeconds": 3600
     }
   ]
   ```
   - In Codespaces, use the `https://<codespace-name>-3000.app.github.dev` address, **not** `https://localhost:3000`. Uploads go from your browser straight to R2, without passing through the Codespaces proxy.
   - Later, add your Vercel address to the same list, for example `["APP_URL", "https://your-app.vercel.app"]`.
   - Never use `"*"`. It would let any website use your upload links.
3. Save.

## 3. Create an API token for this bucket only
1. On the R2 overview page, click **Manage R2 API Tokens** (or **API** > **Manage API tokens**), then **Create API Token**.
2. Set:
   - **Permissions:** **Object Read & Write**. Not Admin.
   - **Specify bucket(s):** **Apply to specific buckets only**, and pick your bucket.
   - **TTL:** Forever is fine for a personal project. You can rotate it any time.
3. Create it, then copy the **Access Key ID** and **Secret Access Key** right away. The secret is shown only once.

## 4. Add the values to `.env`
Find your **Account ID** on the R2 overview page. It's 32 characters. Then fill in these lines in `.env`:
```
R2_ACCOUNT_ID=your account id
R2_ACCESS_KEY_ID=your access key id
R2_SECRET_ACCESS_KEY=your secret access key
R2_BUCKET=your bucket name
```
Leave `R2_ENDPOINT` empty. Never paste these into code, chats or `.env_example`.

## 5. Optional: a usage alert
In the Cloudflare dashboard, look under **Notifications** for a billing or usage alert, and set one up if your account offers it. It's a backup to the app's own 9 GB limit.

## How deleting works
- Deleting a note or project removes its files from the app right away.
- The files themselves stay in R2 for **7 days**, then the app removes them for good. Until then they still count toward the 9 GB limit.
- **To recover a file within those 7 days:** in the Neon console's **SQL Editor**, run:
  ```sql
  select original_name, r2_key, deleted_at from deleted_objects order by deleted_at desc;
  ```
  Then, in your R2 bucket's **Objects** list, search for the `r2_key` and download it.

## If a key ever leaks
In **Manage R2 API Tokens**, delete the token, create a new one with the same settings, and update `.env` and Vercel. The old key stops working right away.
