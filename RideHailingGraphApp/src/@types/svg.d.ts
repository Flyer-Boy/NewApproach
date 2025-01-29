// svg.d.ts

declare module "*.svg?react" {
  import { ReactElement, SVGProps } from "react";
  const content: (props: SVGProps<SVGSVGElement>) => ReactElement;
  export default content;
}
