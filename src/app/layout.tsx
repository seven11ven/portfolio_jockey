import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Portfolio Jockey",
  description: "A private portfolio of projects, notes and media.",
  // Private app: ask search engines not to index any page.
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col font-sans text-[15px] leading-normal">
        {children}
      </body>
    </html>
  );
}
