import { createMultiStyleConfigHelpers } from "@chakra-ui/react";
import { switchAnatomy } from "@chakra-ui/anatomy";

const { definePartsStyle, defineMultiStyleConfig } =
  createMultiStyleConfigHelpers(switchAnatomy.keys);

const baseStyle = definePartsStyle({
  container: {
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    width: "40px ",
    height: "24px",
    border: "0.508px solid #A0AEC0",
    borderRadius: "30px",
    bg: "#A0AEC0",

    _checked: {
      bg: "primary.800",
      border: "none",
    },
  },
  thumb: {
    bg: "white",
    margin: "0px -1px ",
    w: "4",
    h: "4",

    py: "2px",
    _checked: {
      margin: "0px 1px ",

      bg: "white",
    },
  },
  track: {
    bg: "transparent",
  },
});

export const Switch = defineMultiStyleConfig({ baseStyle });
