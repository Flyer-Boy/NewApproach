import { HStack, Text } from "@chakra-ui/react";
import { SidebarItemsProps } from "@ride-hailing/@types/props";
import { useLocation, useNavigate } from "react-router-dom";

const SidebarItems = ({ data }: { data: SidebarItemsProps }) => {
  const { pathname } = useLocation();
  const isActive = pathname === data.link;

  const navigate = useNavigate();

  return (
    <div>
      <HStack
        p={"12px"}
        bg={isActive ? "primary.800" : ""}
        gap={2}
        sx={{
          svg: { path: { fill: isActive ? "gray.lightest" : "primary.800" } },
        }}
        borderRadius={"12px"}
        onClick={() => navigate(data.link)}
        cursor={"pointer"}
      >
        {data.icon}
        <Text
          whiteSpace={"nowrap"}
          variant={"subtitle2"}
          color={isActive ? "gray.lightest" : "primary.800"}
          fontWeight={isActive ? "600" : "500"}
        >
          {data.name}
        </Text>
      </HStack>
    </div>
  );
};

export default SidebarItems;
