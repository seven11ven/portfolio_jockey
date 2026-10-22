import "server-only";
import { sql } from "drizzle-orm";
import { db } from "@/db";

/**
 * A safety guard for Vercel Blob's free Hobby allowance.
 *
 * Going over ANY Hobby limit locks the whole Blob store for 30 days. Vercel
 * never bills Hobby users, but a month without files is bad enough. So the
 * app keeps its own estimate of usage over the last 30 days and refuses
 * actions that would cross 90% of a limit.
 *
 * Estimates are deliberately pessimistic: every view is counted as a full
 * download that missed the cache, even though the real cost is often lower.
 *
 * Hobby allowances, from https://vercel.com/docs/vercel-blob/usage-and-pricing:
 * 2,000 advanced operations, 10,000 simple operations, 10 GB data transfer.
 */
export const BLOB_LIMITS = {
  advancedOps: 1_800, // 90% of 2,000 (uploads, upload parts, token requests)
  simpleOps: 9_000, // 90% of 10,000 (file info checks, uncached views)
  transferBytes: 9_000_000_000, // 90% of 10 GB (views and downloads)
} as const;

export type BlobUsage = { advancedOps?: number; simpleOps?: number; transferBytes?: number };
export type BlobLimitResource = keyof typeof BLOB_LIMITS;

const WINDOW_DAYS = 30;

/**
 * Records planned usage if it fits under the limits. Returns false (and
 * records nothing) if it would go over. A database lock makes this safe
 * when several requests arrive at once.
 */
export async function reserveBlobUsage(usage: BlobUsage): Promise<boolean> {
  const a = usage.advancedOps ?? 0;
  const s = usage.simpleOps ?? 0;
  const t = usage.transferBytes ?? 0;
  const [, inserted] = await db.batch([
    db.execute(sql`select pg_advisory_xact_lock(hashtext('blob-usage'))`),
    db.execute<{ id: string }>(sql`
      with recent as (
        select coalesce(sum(advanced_ops), 0) as a,
               coalesce(sum(simple_ops), 0) as s,
               coalesce(sum(transfer_bytes), 0) as t
        from blob_usage_events
        where at > now() - make_interval(days => ${WINDOW_DAYS})
      )
      insert into blob_usage_events (advanced_ops, simple_ops, transfer_bytes)
      select ${a}, ${s}, ${t}::bigint
      from recent
      where recent.a + ${a} <= ${BLOB_LIMITS.advancedOps}
        and recent.s + ${s} <= ${BLOB_LIMITS.simpleOps}
        and recent.t + ${t}::bigint <= ${BLOB_LIMITS.transferBytes}::bigint
      returning id
    `),
  ]);
  return inserted.rows.length > 0;
}

/** Estimated usage over the last 30 days, for showing on the dashboard. */
export async function getBlobUsage() {
  const result = await db.execute<{ a: string; s: string; t: string }>(sql`
    select coalesce(sum(advanced_ops), 0) as a,
           coalesce(sum(simple_ops), 0) as s,
           coalesce(sum(transfer_bytes), 0) as t
    from blob_usage_events
    where at > now() - make_interval(days => ${WINDOW_DAYS})
  `);
  const row = result.rows[0];
  return {
    advancedOps: Number(row?.a ?? 0),
    simpleOps: Number(row?.s ?? 0),
    transferBytes: Number(row?.t ?? 0),
    limits: BLOB_LIMITS,
  };
}

/** Removes records older than the window. Called from storage cleanup. */
export async function pruneBlobUsage() {
  await db.execute(sql`delete from blob_usage_events where at < now() - make_interval(days => ${WINDOW_DAYS + 1})`);
}
