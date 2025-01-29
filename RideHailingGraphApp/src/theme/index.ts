import { extendTheme } from "@chakra-ui/react";
import colors from "./colors";
import breakpoints from "./breakpoints";
import Text from "./components/Text";
import Button from "./components/Button";
import { Switch } from "./components/Switch";

const theme = extendTheme({
  colors,
  breakpoints,
  components: { Text, Button, Switch },
});
export default theme;
