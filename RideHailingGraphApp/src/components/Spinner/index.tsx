import { Box } from "@chakra-ui/react";
import React from "react";
import styled, { keyframes } from "styled-components";

// Define the props interface
type SpinnerProps = {
  color?: string;
  size?: number;
  sizeUnit?: string;
  scale?: number;
};

// Keyframes function with typed props
const motion = () => keyframes`
  0% {
    opacity: 1;
  }
  100% {
    opacity: 0;
  }
`;

// Styled component with typed props
const Spinner = styled.div<SpinnerProps>`
  color: official;
  display: inline-block;
  position: relative;
  width: ${(p) => `${p.size}${p.sizeUnit}`};
  height: ${(p) => `${p.size}${p.sizeUnit}`};

  div {
    transform-origin: 32px 32px;
    animation: ${() => motion()} 1.2s linear infinite;
  }

  div:after {
    content: " ";
    display: block;
    position: absolute;
    top: 3px;
    left: 29px;
    width: 4px;
    height: 14px;
    border-radius: 20%;
    background: ${(p) => p.color};
  }

  div:nth-child(1) {
    transform: rotate(0deg);
    animation-delay: -1.1s;
  }
  div:nth-child(2) {
    transform: rotate(30deg);
    animation-delay: -1s;
  }
  div:nth-child(3) {
    transform: rotate(60deg);
    animation-delay: -0.9s;
  }
  div:nth-child(4) {
    transform: rotate(90deg);
    animation-delay: -0.8s;
  }
  div:nth-child(5) {
    transform: rotate(120deg);
    animation-delay: -0.7s;
  }
  div:nth-child(6) {
    transform: rotate(150deg);
    animation-delay: -0.6s;
  }
  div:nth-child(7) {
    transform: rotate(180deg);
    animation-delay: -0.5s;
  }
  div:nth-child(8) {
    transform: rotate(210deg);
    animation-delay: -0.4s;
  }
  div:nth-child(9) {
    transform: rotate(240deg);
    animation-delay: -0.3s;
  }
  div:nth-child(10) {
    transform: rotate(270deg);
    animation-delay: -0.2s;
  }
  div:nth-child(11) {
    transform: rotate(300deg);
    animation-delay: -0.1s;
  }
  div:nth-child(12) {
    transform: rotate(330deg);
    animation-delay: 0s;
  }
`;

// React functional component with props
const CustomSpinner: React.FC<SpinnerProps> = ({
  color = "#ADADADCC",
  size = 64,
  sizeUnit = "px",
  scale = 0.5,
}) => (
  <Box sx={{ transform: `scale(${scale})` }}>
    <Spinner color={color} size={size} sizeUnit={sizeUnit}>
      {Array.from({ length: 12 }).map((_, index) => (
        <div key={index} />
      ))}
    </Spinner>
  </Box>
);

export default CustomSpinner;
