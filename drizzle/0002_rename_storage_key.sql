ALTER TABLE "deleted_objects" RENAME COLUMN "r2_key" TO "storage_key";--> statement-breakpoint
ALTER TABLE "files" RENAME COLUMN "r2_key" TO "storage_key";--> statement-breakpoint
ALTER TABLE "files" DROP CONSTRAINT "files_r2Key_unique";--> statement-breakpoint
ALTER TABLE "files" ADD CONSTRAINT "files_storageKey_unique" UNIQUE("storage_key");