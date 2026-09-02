import "./globals.css";

export const metadata = {
  title: "Layer X",
  description: "The world isn't empty. You're just not seeing it yet."
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
