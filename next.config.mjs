/** @type {import('next').NextConfig} */
const nextConfig = {
  ...(process.env.PERKRADAR_DESKTOP === "1" ? { output: "standalone" } : {}),
  distDir: process.env.NEXT_DIST_DIR || ".next",
  serverExternalPackages: ["node:sqlite"],
};

export default nextConfig;
