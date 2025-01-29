import { Box, HStack, Stack, Text, VStack } from "@chakra-ui/react";
import { LineIcon, PointIcon } from "@ride-hailing/assets/svg";
import colors from "@ride-hailing/theme/colors";

const FromTo = ({ from, to }: { from: string; to: string }) => {
  return (
    <HStack borderRadius={"2xl"} border={"1px solid #EBEBEB"} p={4}>
      <HStack>
        <VStack gap={1}>
          <HStack
            sx={{
              boxSize: "18px",
              borderRadius: "50%",
              justifyContent: "center",
              overflow: "hidden",
              border: `2px solid ${colors.primary[800]}`,
            }}
          >
            <Box
              sx={{
                width: "6px",
                height: "6px",
                borderRadius: "50%",
                bg: "black",
              }}
            />
          </HStack>
          <LineIcon />
          <PointIcon />
        </VStack>

        <Stack mt={4}>
          <Stack gap={1} mb={3}>
            <Text color={"gray.normal"} variant={"subtitle2"}>
              Pickup
            </Text>
            <Text variant={"subtitle2"} pb={1}>
              {from}
            </Text>
          </Stack>
          <Stack gap={1}>
            <Text color={"gray.normal"} variant={"subtitle2"}>
              Drop Off
            </Text>
            <Text variant={"subtitle2"}>{to}</Text>
          </Stack>
        </Stack>
      </HStack>
    </HStack>
  );
};

export default FromTo;
