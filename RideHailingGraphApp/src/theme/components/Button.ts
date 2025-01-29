import { defineStyle, defineStyleConfig } from "@chakra-ui/react";

const primary = defineStyle({
  bg: "primary.800",
  p: "14px 32px",
  color: "white",
  fontSize: "14px",
  fontWeight: "500",
  height: "44px",
  borderRadius: "12px",
  svg: { path: { stroke: "white" } },
});

const ghost = defineStyle({
  bg: "#E6E6E6",
  p: "14px 32px",
  color: "primary.800",
  fontSize: "14px",
  fontWeight: "500",
  height: "48px",
  borderRadius: "12px",
  svg: { path: { stroke: "primary.800" } },
});

const Button = defineStyleConfig({
  variants: {
    primary,
    ghost,
  },
  defaultProps: {
    variant: "primary",
  },
});

export default Button;
