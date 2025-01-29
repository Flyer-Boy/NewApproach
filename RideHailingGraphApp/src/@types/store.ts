export type PassengerStoreType = {
  bookingId: string;
  stage: string;
  reload: boolean;
  rideCount: number;

  setRideCount: (rideCount: number) => void;
  setBookingId: (id: string) => void;
  setStage: (stage: string) => void;
  setReload: (reload: boolean) => void;
};
