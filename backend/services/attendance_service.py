from sqlalchemy.orm import Session
from sqlalchemy import and_, func
from datetime import datetime, date, timedelta
from models import AttendanceRecord, AttendanceStatus
import math


class AttendanceService:
    """Service for attendance tracking operations"""
    
    @staticmethod
    def check_in_worker(db: Session, worker_id: int, project_id: int,
                       location: str = None, method: str = 'Geofence') -> AttendanceRecord:
        """Record worker check-in"""
        record = AttendanceRecord(
            worker_id=worker_id,
            project_id=project_id,
            check_in_time=datetime.utcnow(),
            location=location,
            method=method,
            date=date.today(),
        )
        
        # Check if this is late (after 07:30)
        check_in_hour = record.check_in_time.hour
        check_in_minute = record.check_in_time.minute
        
        if check_in_hour > 7 or (check_in_hour == 7 and check_in_minute > 30):
            record.status = AttendanceStatus.LATE
        else:
            record.status = AttendanceStatus.PRESENT
        
        db.add(record)
        db.commit()
        db.refresh(record)
        return record
    
    @staticmethod
    def check_out_worker(db: Session, worker_id: int, project_id: int) -> AttendanceRecord:
        """Record worker check-out and calculate hours worked"""
        today = date.today()
        record = db.query(AttendanceRecord).filter(
            and_(
                AttendanceRecord.worker_id == worker_id,
                AttendanceRecord.project_id == project_id,
                func.date(AttendanceRecord.date) == today,
                AttendanceRecord.check_out_time == None
            )
        ).first()
        
        if not record:
            return None
        
        record.check_out_time = datetime.utcnow()
        
        # Calculate hours worked
        if record.check_in_time:
            time_diff = record.check_out_time - record.check_in_time
            hours_worked = time_diff.total_seconds() / 3600
            record.hours_worked = round(hours_worked, 2)
        
        db.commit()
        db.refresh(record)
        return record
    
    @staticmethod
    def mark_absent(db: Session, worker_id: int, project_id: int) -> AttendanceRecord:
        """Mark worker as absent"""
        today = date.today()
        
        # Check if record already exists
        existing = db.query(AttendanceRecord).filter(
            and_(
                AttendanceRecord.worker_id == worker_id,
                AttendanceRecord.project_id == project_id,
                func.date(AttendanceRecord.date) == today
            )
        ).first()
        
        if existing:
            existing.status = AttendanceStatus.ABSENT
            existing.check_in_time = None
            existing.check_out_time = None
            db.commit()
            db.refresh(existing)
            return existing
        
        record = AttendanceRecord(
            worker_id=worker_id,
            project_id=project_id,
            status=AttendanceStatus.ABSENT,
            date=today,
        )
        
        db.add(record)
        db.commit()
        db.refresh(record)
        return record
    
    @staticmethod
    def get_attendance_for_date(db: Session, record_date: date, project_id: int = None) -> list:
        """Get attendance records for a specific date"""
        query = db.query(AttendanceRecord).filter(
            func.date(AttendanceRecord.date) == record_date
        )
        
        if project_id:
            query = query.filter(AttendanceRecord.project_id == project_id)
        
        return query.all()
    
    @staticmethod
    def get_attendance_stats(db: Session, record_date: date, project_id: int = None) -> dict:
        """Get attendance statistics for a date"""
        records = AttendanceService.get_attendance_for_date(db, record_date, project_id)
        
        total = len(records)
        present = len([r for r in records if r.status == AttendanceStatus.PRESENT])
        late = len([r for r in records if r.status == AttendanceStatus.LATE])
        absent = len([r for r in records if r.status == AttendanceStatus.ABSENT])
        
        attendance_rate = (present / total * 100) if total > 0 else 0
        
        return {
            'total': total,
            'present': present,
            'late': late,
            'absent': absent,
            'attendance_rate': round(attendance_rate, 2),
        }
    
    @staticmethod
    def get_worker_attendance_history(db: Session, worker_id: int, days: int = 30) -> list:
        """Get worker attendance history for past N days"""
        start_date = date.today() - timedelta(days=days)
        
        records = db.query(AttendanceRecord).filter(
            and_(
                AttendanceRecord.worker_id == worker_id,
                func.date(AttendanceRecord.date) >= start_date
            )
        ).order_by(AttendanceRecord.date.desc()).all()
        
        return records
    
    @staticmethod
    def get_weekly_attendance_data(db: Session, project_id: int = None) -> list:
        """Get weekly attendance trend data"""
        days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        weekly_data = []
        
        for i in range(7):
            day_date = date.today() - timedelta(days=6-i)
            stats = AttendanceService.get_attendance_stats(db, day_date, project_id)
            
            weekly_data.append({
                'day': days[i],
                'present': stats['present'],
                'late': stats['late'],
                'absent': stats['absent'],
            })
        
        return weekly_data
    
    @staticmethod
    def get_total_hours_worked(db: Session, worker_id: int, start_date: date = None,
                              end_date: date = None) -> float:
        """Get total hours worked by a worker in a period"""
        query = db.query(func.sum(AttendanceRecord.hours_worked)).filter(
            AttendanceRecord.worker_id == worker_id
        )
        
        if start_date:
            query = query.filter(AttendanceRecord.date >= start_date)
        if end_date:
            query = query.filter(AttendanceRecord.date <= end_date)
        
        total = query.scalar() or 0.0
        return round(total, 2)
