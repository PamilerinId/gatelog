import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    formats: ["image/avif", "image/webp"],
    // Next 16 only serves listed qualities; these are the ones the page asks for.
    qualities: [70, 75, 80, 82],
  },
  poweredByHeader: false,
};

export default nextConfig;
