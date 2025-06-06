import { Avatar, Box, HStack, Stack, Text } from "@chakra-ui/react";
import { DriverListProps } from "@ride-hailing/@types/props";
import { VehicleIcon } from "@ride-hailing/assets/svg";
import { ROUTES } from "@ride-hailing/routes/routes.constant";
import { useUserData } from "@ride-hailing/store";
import { useNavigate } from "react-router-dom";

const DriverCard = ({ data }: { data: DriverListProps }) => {
  const {
    Status,
    ID,
    Name,
    Email,
    Phone,
    Photo,
    License,
    Color,
    Make,
    Model,
    Plate,
  } = data;
  const navigate = useNavigate();

  const { setStage, setReload } = useUserData();

  return (
    <HStack
      justifyContent={"space-between"}
      border={"1px solid #ebebeb"}
      p={5}
      borderRadius={"2xl"}
      cursor={"pointer"}
      onClick={() => {
        sessionStorage.setItem("driverId", ID);

        setStage("INITIAL");
        navigate(ROUTES.HOME);
        setReload(true);
      }}
    >
      <HStack flex={1}>
        <Avatar src={Photo} name={Name} size={"lg"} />
        <Stack gap={0}>
          <Text variant={"pNormal"} fontWeight={600}>
            {Name}{" "}
            <span style={{ color: Status === "Available" ? "green" : "red" }}>
              ({Status})
            </span>
          </Text>
          <Text fontSize={"13px"} color={"gray.dark"}>
            {Email}
          </Text>
        </Stack>
      </HStack>

      <HStack justifyContent="center" alignItems={"flex-start"} flex={1}>
        <Box mt={1}>
          <VehicleIcon />
        </Box>
        <Stack gap={0}>
          <Text
            whiteSpace={"nowrap"}
            color="gray.darkest"
            variant={"subtitle2"}
          >
            {Color} - {Make} {Model}
          </Text>

          <Text variant={"pSmall"} color={"gray.normal"}>
            Ph: {Phone}
          </Text>
        </Stack>
      </HStack>

      <HStack justifyContent="center" alignItems={"flex-start"} flex={1}>
        <Stack gap={0}>
          <HStack gap={1}>
            <Text whiteSpace={"nowrap"} fontWeight={600} variant={"pSmall"}>
              {Plate}
            </Text>
            <Box borderRadius={"50%"} boxSize={"12px"} />
            <Text
              whiteSpace={"nowrap"}
              fontWeight={600}
              variant={"pSmall"}
            ></Text>
            <Text
              whiteSpace={"nowrap"}
              color="gray.normal"
              variant={"subtitle2"}
            >
              ({data?.Capacity?.toString()} seater)
            </Text>
          </HStack>
          <Text fontSize={"13px"} color={"gray.normal"}>
            Lic: {License}
          </Text>
        </Stack>
      </HStack>
    </HStack>
  );
};

export default DriverCard;
