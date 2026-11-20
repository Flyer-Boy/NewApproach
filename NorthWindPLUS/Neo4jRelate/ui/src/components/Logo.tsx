import { Image } from "@chakra-ui/react";

/** The original Northwind Traders logo (the sample dataset NorthWind PLUS is built from), served from ui/public. */
export default function Logo({ size = "48px" }: { size?: string }) {
  return (
    <Image src="/northwind.webp" alt="Northwind Traders" boxSize={size} objectFit="contain"
           borderRadius="md" borderWidth="1px" bg="white" p="2px" flexShrink={0} />
  );
}
