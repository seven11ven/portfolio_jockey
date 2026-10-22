CREATE TABLE "blob_usage_events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"at" timestamp with time zone DEFAULT now() NOT NULL,
	"advanced_ops" integer DEFAULT 0 NOT NULL,
	"simple_ops" integer DEFAULT 0 NOT NULL,
	"transfer_bytes" bigint DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE INDEX "blob_usage_events_at_idx" ON "blob_usage_events" USING btree ("at");