import { Box, Container, Stack } from "@chakra-ui/react";
import { LayoutProps } from "@ride-hailing/@types/props";
import Sidebar from "./Sidebar";
import Navbar from "./Navbar";

const Layout = ({ children, onlyNavbar = false }: LayoutProps) => {
  return (
    <Stack overflow={"hidden"} h={"100vh"}>
      <Box>
        <Navbar />
      </Box>
      <Container maxW={{ base: "100%", xl: "75%" }} py={6}>
        {!onlyNavbar ? <Sidebar element={children} /> : children}
      </Container>
    </Stack>
  );
};

export default Layout;
