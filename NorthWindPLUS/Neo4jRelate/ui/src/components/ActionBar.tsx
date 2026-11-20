import { ReactNode } from "react";
import { Box, Flex } from "@chakra-ui/react";

/** The screen's main actions, pinned to the bottom of the window however many cards there are. A spacer keeps the
 *  last card from hiding behind it. (position: sticky didn't hold inside the tabs on long pages; fixed always does.) */
export default function ActionBar({ children }: { children: ReactNode }) {
  return (
    <>
      <Box h="80px" />
      <Box position="fixed" left={0} right={0} bottom={0} zIndex={10} bg="bg" borderTopWidth="1px" boxShadow="md">
        <Flex maxW="1200px" mx="auto" px={6} py={3} justify="space-between" align="center" gap={3} wrap="wrap">
          {children}
        </Flex>
      </Box>
    </>
  );
}
