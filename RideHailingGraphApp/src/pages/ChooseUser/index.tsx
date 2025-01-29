import { Center, HStack, Stack, Text, VStack } from "@chakra-ui/react";
import UserTypeCard from "./UserTypeCard";
import { DriverIcon, PassengerIcon } from "@ride-hailing/assets/svg";

const userTypeLabel = [
  {
    icon: <PassengerIcon />,
    name: "Passenger",
    title: "Choose your destination",
  },
  {
    icon: <DriverIcon />,
    name: "Driver",
    title: "Stay online to receive ride request.",
  },
];

const ChooseUser = () => {
  return (
    <Center mt={"80px"}>
      <Stack
        p={"48px 202px 60px 202px"}
        bg={"white"}
        w={"1000px"}
        borderRadius={"16px"}
        gap={8}
      >
        <VStack>
          <Text variant={"h4"}>User Type</Text>
          <Text variant={"subtitle1"} fontWeight={400}>
            Please select a user role to continue: Passenger or
            Driver.
          </Text>
        </VStack>
        <HStack gap={4}>
          {userTypeLabel?.map((item, index) => (
            <UserTypeCard
              key={index}
              icon={item.icon}
              name={item.name}
              title={item.title}
            />
          ))}
        </HStack>
      </Stack>
    </Center>
  );
};

export default ChooseUser;
