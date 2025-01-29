import { defineStyle, defineStyleConfig } from "@chakra-ui/react";

const h1 = defineStyle({
  fontWeight: 700,
  fontSize: "32px",
  lineHeight: "38.4px",
});

const h2 = defineStyle({
  fontWeight: 700,
  fontSize: "29px",
  lineHeight: "34.8px",
});

const h3 = defineStyle({
  fontWeight: 600,
  fontSize: "26px",
  lineHeight: "31.2px",
});

const h4 = defineStyle({
  fontWeight: 600,
  fontSize: "23px",
  lineHeight: "27.6px",
});

const h5 = defineStyle({
  fontWeight: 600,
  fontSize: "20px",
  lineHeight: "24px",
});

const h6 = defineStyle({
  fontWeight: 500,
  fontSize: "18px",
  lineHeight: "21.6px",
});

const subtitle1 = defineStyle({
  fontWeight: 500,
  fontSize: "16px",
  lineHeight: "19.2px",
});

const subtitle2 = defineStyle({
  fontWeight: 500,
  fontSize: "14px",
  lineHeight: "16.8px",
});

const pLarge = defineStyle({
  fontWeight: 400,
  fontSize: "54px",
  lineHeight: "24px",
});
const pRegular = defineStyle({
  fontWeight: 400,
  fontSize: "14px",
  lineHeight: "20px",
});

const pSmall = defineStyle({
  fontWeight: 400,
  fontSize: "13px",
  lineHeight: "20px",
});

const Text = defineStyleConfig({
  variants: {
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    subtitle1,
    subtitle2,
    pLarge,
    pRegular,
    pSmall,
  },
});

export default Text;
