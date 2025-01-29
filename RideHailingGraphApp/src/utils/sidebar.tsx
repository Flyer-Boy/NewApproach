import {
  BookingIcon,
  HomeIcon,
  TransactionIcon,
} from "@ride-hailing/assets/svg";
import { ROUTES } from "@ride-hailing/routes/routes.constant";

export const sidebarItems = [
  {
    name: "Home",
    icon: <HomeIcon />,
    link: ROUTES.HOME,
  },
  {
    name: "Transaction",
    icon: <TransactionIcon />,
    link: ROUTES.TRANSACTION,
  },
  {
    name: "Previous Booking",
    icon: <BookingIcon />,
    link: ROUTES.PREVIOUS_BOOKING,
  },
];
