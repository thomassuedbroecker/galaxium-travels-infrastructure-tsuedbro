from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from models import User, Flight, Booking
from db import get_db, init_db
from seed import seed
from pydantic import BaseModel
from datetime import datetime

app = FastAPI()

@app.on_event("startup")
def on_startup():
    init_db()
    seed()

class FlightOut(BaseModel):
    flight_id: int
    origin: str
    destination: str
    departure_time: str
    arrival_time: str
    price: int
    seats_available: int
    class Config:
        orm_mode = True

class BookingIn(BaseModel):
    user_id: int
    name: str
    flight_id: int

class BookingOut(BaseModel):
    booking_id: int
    user_id: int
    flight_id: int
    status: str
    booking_time: str
    class Config:
        orm_mode = True

class UserIn(BaseModel):
    name: str
    email: str

class UserOut(BaseModel):
    user_id: int
    name: str
    email: str
    class Config:
        orm_mode = True

@app.get(
    "/flights",
    response_model=list[FlightOut],
    summary="List all available flights",
    description="Retrieve a list of all available flights, including origin, destination, departure and arrival times, price, and the number of seats currently available for booking."
)
def list_flights(db: Session = Depends(get_db)):
    return db.query(Flight).all()

@app.post(
    "/book",
    response_model=BookingOut,
    summary="Book a flight for a user",
    description="Book a seat on a specific flight for a user. Requires user_id, name, and flight_id in the request body. If the flight has available seats and the user_id matches the name, a new booking is created and the number of available seats is decremented by one. Returns the booking details."
)
def book_flight(booking: BookingIn, db: Session = Depends(get_db)):
    flight = db.query(Flight).filter(Flight.flight_id == booking.flight_id).first()
    if not flight:
        raise HTTPException(status_code=404, detail="Flight not found")
    if flight.seats_available < 1:
        raise HTTPException(status_code=400, detail="No seats available")
    user = db.query(User).filter(User.user_id == booking.user_id, User.name == booking.name).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found or name does not match user ID")
    # Decrement seat
    flight.seats_available -= 1
    new_booking = Booking(
        user_id=booking.user_id,
        flight_id=booking.flight_id,
        status="booked",
        booking_time=datetime.utcnow().isoformat()
    )
    db.add(new_booking)
    db.commit()
    db.refresh(new_booking)
    db.commit()
    return new_booking

@app.get(
    "/bookings/{user_id}",
    response_model=list[BookingOut],
    summary="List all bookings for a user",
    description="Retrieve all bookings for a specific user by user_id. Returns a list of bookings, including booking status and booking time, for the given user."
)
def get_bookings(user_id: int, db: Session = Depends(get_db)):
    return db.query(Booking).filter(Booking.user_id == user_id).all()

@app.post(
    "/cancel/{booking_id}",
    response_model=BookingOut,
    summary="Cancel a booking by booking ID",
    description="Cancel an existing booking by its booking_id. If the booking is active, its status is set to 'cancelled' and the number of available seats for the associated flight is incremented by one. Returns the updated booking details."
)
def cancel_booking(booking_id: int, db: Session = Depends(get_db)):
    booking = db.query(Booking).filter(Booking.booking_id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    if booking.status == "cancelled":
        raise HTTPException(status_code=400, detail="Booking already cancelled")
    flight = db.query(Flight).filter(Flight.flight_id == booking.flight_id).first()
    if flight:
        flight.seats_available += 1
    booking.status = "cancelled"
    db.commit()
    db.refresh(booking)
    return booking

@app.post(
    "/register",
    response_model=UserOut,
    summary="Register a new user",
    description="Register a new user with a name and unique email. Returns the created user."
)
def register_user(user: UserIn, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == user.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    new_user = User(name=user.name, email=user.email)
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user

@app.get(
    "/user_id",
    response_model=UserOut,
    summary="Get user by name and email",
    description="Retrieve a user's information (including user_id) by providing both name and email. Returns 404 if not found."
)
def get_user_id(name: str, email: str, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.name == name, User.email == email).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user 