import { Avatar, HStack, Stack, Text } from "@chakra-ui/react";
import { CarIcon } from "@ride-hailing/assets/svg";
import { useUserData } from "@ride-hailing/store";
import { useMemo } from "react";

type ProfileInformationType = {
  Name: string;
  Email: string;
  Phone: number;
  Photo: string;
};

const UserProfileCard = ({ data }: { data: ProfileInformationType }) => {
  const userType = sessionStorage.getItem("userType");

  const { rideCount } = useUserData();

  const userDetails = useMemo(() => {
    return [
      {
        icon: <CarIcon />,
        label: "Total Rides",
        value: rideCount,
      },
    ];
  }, [userType, data, rideCount]);

  return (
    <Stack w={"100%"} flexDir={"row"} p={8} justifyContent={"space-between"}>
      <HStack>
        <Avatar
          src={data?.Photo}
          name={data?.Name}
          size={"lg"}
          border={"2px solid"}
        />
        <Stack gap={0}>
          <Text fontSize={20} fontWeight={600}>
            {data?.Name}
          </Text>
          <Text fontWeight={400}>Email: {data?.Email} / Ph: {data?.Phone}</Text>
        </Stack>
      </HStack>

      <Stack gap={4} mx={5}>
        {userDetails?.map((item, index) => (
          <HStack key={index} justifyContent={"space-between"} gap={10}>
            <HStack gap={2}>
              {item.icon}
              <Text whiteSpace={"nowrap"} variant={"subtitle2"}>
                {item.label}
              </Text>
            </HStack>
            <HStack>
              <Text
                variant={"subtitle1"}
                fontWeight={700}
                whiteSpace={"nowrap"}
              >
                {item.value}
              </Text>
            </HStack>
          </HStack>
        ))}
      </Stack>
    </Stack>
  );
};

export default UserProfileCard;
