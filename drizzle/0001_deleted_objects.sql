CREATE TABLE "deleted_objects" (
	"r2_key" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"original_name" text NOT NULL,
	"mime_type" text NOT NULL,
	"size_bytes" bigint NOT NULL,
	"deleted_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX "deleted_objects_user_idx" ON "deleted_objects" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "deleted_objects_deleted_at_idx" ON "deleted_objects" USING btree ("deleted_at");