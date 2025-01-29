import {
  FormControl,
  FormErrorMessage,
  FormLabel,
  Text,
} from "@chakra-ui/react";
import { FormWrapperProps } from "@ride-hailing/@types/props";

const FormWrapper = ({
  error,
  label,
  labelSize,
  children,
  isRequired,
  showErrorMessage = true,
}: FormWrapperProps) => {
  const errorMessage = error?.message;

  return (
    <FormControl variant="floating" isInvalid={!!error}>
      {label && (
        <FormLabel>
          <Text variant="subtitle2" as="span" fontSize={labelSize}>
            {label}
          </Text>
          {isRequired ? (
            <Text as={"span"} color={"red.500"}>
              *
            </Text>
          ) : (
            ""
          )}
        </FormLabel>
      )}
      {children}
      {errorMessage && showErrorMessage && (
        <FormErrorMessage marginTop={1} color={"danger.300"} pl={1}>
          {errorMessage}
        </FormErrorMessage>
      )}
    </FormControl>
  );
};

export default FormWrapper;
