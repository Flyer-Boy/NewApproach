import { Center, Text, VStack } from "@chakra-ui/react";
import { ROUTES } from "@ride-hailing/routes/routes.constant";
import { ReactNode } from "react";
import { useNavigate } from "react-router-dom";

type UserTypeCardTypes = {
  icon: ReactNode;
  name: string;
  title: string;
};

const UserTypeCard = ({ icon, name, title }: UserTypeCardTypes) => {
  const navigate = useNavigate();
  const getRoute = (userType: string) => {
    switch (userType) {
      case "DRIVER":
        return ROUTES.DRIVER_LIST;
      case "PASSENGER":
        return ROUTES.PASSENGER_LIST;
      default:
        return "";
    }
  };

  return (
    <Center
      px={"24px"}
      border={"1px solid #EBEBEB"}
      borderRadius={"16px"}
      width=" 288px"
      height=" 228px"
      _hover={{ bg: "gray.lightest" }}
      cursor={"pointer"}
      onClick={() => {
        localStorage.setItem("userType", name.toUpperCase());
        navigate(getRoute(name.toUpperCase()));
      }}
    >
      <VStack gap={8}>
        <Center
          background=" linear-gradient(144deg, #505050 32.57%, #000 87.48%)"
          boxSize={"60px"}
          borderRadius={"50%"}
        >
          {icon}
        </Center>
        <VStack>
          <Text variant={"h5"}>{name}</Text>
          <Text variant={"pRegular"} fontWeight={400}>
             {title}
          </Text>
        </VStack>
      </VStack>
    </Center>
  );
};

export default UserTypeCard;
