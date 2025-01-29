import { Avatar, HStack, Stack, Text } from "@chakra-ui/react";
import { PassengerListProps } from "@ride-hailing/@types/props";
import { ROUTES } from "@ride-hailing/routes/routes.constant";
import { useUserData } from "@ride-hailing/store";
import { useNavigate } from "react-router-dom";

const PassengerCard = ({ data }: { data: PassengerListProps }) => {
  const { Status, Name, Email, Phone, Photo } = data;

  const navigate = useNavigate();

  const { setStage, setReload } = useUserData();
  return (
    <HStack
      justifyContent={"space-between"}
      gap={0}
      border={"1px solid #ebebeb"}
      p={5}
      borderRadius={"2xl"}
      cursor={"pointer"}
      onClick={() => {
        localStorage.setItem("userTypeId", String(Phone));
        setStage("INITIAL");
        navigate(ROUTES.HOME);
        setReload(true);
      }}
      _hover={{ bg: "gray.lightest" }}
    >
      <HStack flex={1}>
        <Avatar src={Photo} name="Biplov" size={"lg"} />
        <Stack gap={0}>
          <Text fontSize={"sm"} fontWeight={600}>
            {Name}
            <span style={{ color: Status === "Available" ? "green" : "red" }}>
              ({Status})
            </span>
          </Text>
          <Text fontSize={"13px"} fontWeight={400} color={"gray.dark"}>
            Email: {Email}
          </Text>
        </Stack>
      </HStack>

      <HStack justifyContent="center" alignItems={"flex-start"} flex={1}>
        <Stack gap={0}>
          <Text
            whiteSpace={"nowrap"}
            color="gray.darkest"
            variant={"subtitle2"}
          ></Text>
          <Text variant={"pSmall"} color={"gray.normal"}>
            Ph: {Phone}
          </Text>
        </Stack>
      </HStack>
    </HStack>
  );
};

export default PassengerCard;
