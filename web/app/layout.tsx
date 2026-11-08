import type { Metadata, Viewport } from "next";
import "./globals.css";
import { requireChatGPTUser } from "./chatgpt-auth";
export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Blue — notes & collections",
  description: "A quiet home for your notes and collections.",
  applicationName: "Blue",
  manifest: "/manifest.webmanifest",
  appleWebApp: { capable: true, statusBarStyle: "default", title: "Blue" },
  icons: { icon: "/favicon.svg", apple: "/apple-touch-icon.png" },
};
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#f7f7f6",
};
export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireChatGPTUser("/");
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
