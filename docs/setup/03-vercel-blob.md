# Setup 3: Vercel Blob file storage

Uploaded images, audio, video and documents are stored in a **private** Vercel Blob store. Nothing in it is public. The app gives the browser short-lived signed links, each allowing one upload or one view of one file.

**You'll need:** about 15 minutes, a GitHub account, and Setups 1 and 2 finished.

## Cost: free, with hard limits
From Vercel's own pricing pages:
- "The Hobby plan is **free**." A card is only asked for if you choose to upgrade to Pro, so don't upgrade.
- Hobby includes, per month: **1 GB** of Blob storage, **10 GB** of Blob data transfer (views and downloads), **2,000** advanced operations (uploads, including each part of a large upload), and **10,000** simple operations.
- "You **will not pay for any additional usage**. However, you will not be able to access Vercel Blob if limits are exceeded." Access stays blocked for **30 days**.
- Hobby is for non-commercial, personal use only.

To avoid that 30-day lockout, the app stops on its own before any limit:
- It refuses uploads past **900 MB** of total storage (`STORAGE_QUOTA_BYTES`).
- It keeps its own estimate of the last 30 days of usage, and refuses uploads or views that would pass **90%** of any monthly allowance. The estimate assumes the worst case, so the app usually stops early.

Sources: [Vercel Blob pricing](https://vercel.com/docs/vercel-blob/usage-and-pricing) and [Hobby plan](https://vercel.com/docs/plans/hobby).

## 1. Create a Vercel account and project
1. Go to [vercel.com](https://vercel.com) and sign up with **Continue with GitHub**. Choose the **Hobby** plan.
2. Click **Add New > Project**, and import this repository.
3. Vercel will try to deploy right away. **It's fine if that first deployment fails.** The app's settings aren't on Vercel yet, and deploying is a later step.

## 2. Create a private Blob store
1. Open your project's **Storage** tab.
2. Click **Create Storage**, choose **Blob**, then **Continue**.
3. Set the access to **Private**, and double-check it before creating the store.
4. Give it a name, such as `portfolio-jockey-files`, and connect it to the project in all environments.

Creating the store adds a `BLOB_READ_WRITE_TOKEN` environment variable to the project.

## 3. Add the token to your local `.env`
1. In the project, open **Settings > Environment Variables**.
2. Find `BLOB_READ_WRITE_TOKEN`, reveal it, and copy the value.
3. Paste it into `.env` in the repo root:
   ```
   BLOB_READ_WRITE_TOKEN=paste the value here
   ```
   Leave `BLOB_STORE_ID` empty locally.

> **This token can read and delete every file in the store.** Treat it like a password. Never paste it into code, chats or `.env_example`.

On Vercel itself you don't need to do anything. Deployed code uses short-lived credentials that Vercel creates and rotates automatically.

## 4. Check it
Run `npm run dev`. The app should start without an "Invalid environment variables" error. Stop it with `Ctrl+C` afterwards, so port 3000 doesn't stay open.

## How deleting works
- Deleting a note or project removes its files from the app right away.
- The files stay in the Blob store for **7 days**, then the app deletes them for good. Deleting is free on Vercel Blob. Until then they still count toward the 900 MB limit.
- **To recover a file within those 7 days:** in the Neon console's **SQL Editor**, run:
  ```sql
  select original_name, storage_key, deleted_at from deleted_objects order by deleted_at desc;
  ```
  Then, in your project's **Storage** tab, open the Blob store, browse to the `storage_key` path and download the file. Browsing in the dashboard counts toward the monthly operations allowance, so keep it brief.

## If the token ever leaks
In the Blob store's settings, rotate or regenerate its read-write token, update `.env`, and redeploy. If you can't find a rotate option, create a new private store, connect it, and move to the new token. The old store's token then no longer matters once that store is deleted.
