from typing import List
from datetime import datetime
import math


class AIService:
    """AI-powered service for intelligent task and worker matching"""
    
    @staticmethod
    def calculate_worker_task_match(worker_skills: List[str], required_skills: List[str],
                                   worker_rating: float, task_priority: str) -> float:
        """
        Calculate AI match score between worker and task (0-100%)
        
        Args:
            worker_skills: List of worker skills
            required_skills: List of required skills for task
            worker_rating: Worker's performance rating (0-5)
            task_priority: Task priority (High, Medium, Low)
        
        Returns:
            Match score percentage (0-100)
        """
        if not required_skills:
            return 100.0
        
        # Skill match calculation (60% weight)
        matching_skills = len(set(worker_skills) & set(required_skills))
        skill_match = (matching_skills / len(required_skills)) * 100 if required_skills else 0
        
        # Rating factor (30% weight) - normalize rating to 0-100
        rating_factor = (worker_rating / 5.0) * 100
        
        # Task priority factor (10% weight)
        priority_factor = {
            'High': 100,
            'Medium': 80,
            'Low': 60,
        }.get(task_priority, 50)
        
        # Weighted calculation
        match_score = (skill_match * 0.6) + (rating_factor * 0.3) + (priority_factor * 0.1)
        
        return round(min(match_score, 100.0), 2)
    
    @staticmethod
    def recommend_workers(workers_list: List[dict], task_requirements: dict) -> List[dict]:
        """
        Recommend best workers for a task using AI matching
        
        Args:
            workers_list: List of available workers with their data
            task_requirements: Task requirements (skills, priority, etc.)
        
        Returns:
            Sorted list of workers with match scores
        """
        recommendations = []
        
        for worker in workers_list:
            match_score = AIService.calculate_worker_task_match(
                worker_skills=worker.get('skills', []),
                required_skills=task_requirements.get('required_skills', []),
                worker_rating=worker.get('rating', 3.0),
                task_priority=task_requirements.get('priority', 'Medium')
            )
            
            recommendations.append({
                'worker_id': worker.get('id'),
                'name': worker.get('name'),
                'role': worker.get('role'),
                'rating': worker.get('rating'),
                'match_score': match_score,
            })
        
        # Sort by match score descending
        recommendations.sort(key=lambda x: x['match_score'], reverse=True)
        
        return recommendations
    
    @staticmethod
    def predict_task_completion_time(task_data: dict, historical_data: List[dict] = None) -> dict:
        """
        Predict task completion time based on task characteristics
        
        Args:
            task_data: Task information (complexity, estimated hours, etc.)
            historical_data: Historical task data for ML training
        
        Returns:
            Prediction with confidence
        """
        estimated_hours = task_data.get('estimated_hours', 8)
        complexity = task_data.get('complexity', 'medium')  # low, medium, high
        
        # Simple prediction model
        complexity_multiplier = {
            'low': 0.8,
            'medium': 1.0,
            'high': 1.3,
        }.get(complexity, 1.0)
        
        predicted_hours = estimated_hours * complexity_multiplier
        
        # Calculate confidence (80% for this simple model)
        confidence = 80
        
        return {
            'estimated_hours': estimated_hours,
            'predicted_hours': round(predicted_hours, 2),
            'complexity': complexity,
            'confidence': confidence,
        }
    
    @staticmethod
    def detect_productivity_anomaly(worker_id: int, historical_data: List[dict]) -> dict:
        """
        Detect unusual patterns in worker productivity
        
        Args:
            worker_id: Worker ID
            historical_data: Historical productivity data
        
        Returns:
            Anomaly detection result
        """
        if not historical_data or len(historical_data) < 3:
            return {
                'has_anomaly': False,
                'message': 'Insufficient data for analysis',
            }
        
        # Calculate average and standard deviation
        values = [d.get('productivity', 0) for d in historical_data]
        avg = sum(values) / len(values)
        
        variance = sum((x - avg) ** 2 for x in values) / len(values)
        std_dev = math.sqrt(variance)
        
        # Check if latest value is more than 2 std dev from mean (anomaly threshold)
        latest = values[-1]
        z_score = (latest - avg) / std_dev if std_dev > 0 else 0
        
        has_anomaly = abs(z_score) > 2
        
        return {
            'has_anomaly': has_anomaly,
            'average_productivity': round(avg, 2),
            'latest_productivity': latest,
            'z_score': round(z_score, 2),
            'message': 'Unusual productivity pattern detected' if has_anomaly else 'Normal productivity pattern',
        }
    
    @staticmethod
    def suggest_resource_optimization(project_data: dict) -> List[str]:
        """
        Suggest resource optimization for project
        
        Args:
            project_data: Project information
        
        Returns:
            List of optimization suggestions
        """
        suggestions = []
        
        # Analyze utilization
        if project_data.get('worker_utilization', 0) < 70:
            suggestions.append('Consider reassigning idle workers to other projects')
        
        if project_data.get('task_efficiency', 0) < 60:
            suggestions.append('Task completion rate is below average. Review task dependencies')
        
        if project_data.get('overtime_hours', 0) > 50:
            suggestions.append('High overtime detected. Consider hiring additional workers')
        
        if project_data.get('accident_rate', 0) > 2:
            suggestions.append('Safety incidents above average. Review safety protocols')
        
        if not suggestions:
            suggestions.append('Project resource allocation is optimized')
        
        return suggestions
    
    @staticmethod
    def predict_delays(project_data: dict) -> dict:
        """
        Predict potential project delays
        
        Args:
            project_data: Project information
        
        Returns:
            Delay prediction with risk level
        """
        risk_score = 0
        risk_factors = []
        
        # Check task completion rate
        if project_data.get('completion_rate', 100) < 50:
            risk_score += 30
            risk_factors.append('Low task completion rate')
        
        # Check productivity trend
        if project_data.get('productivity_trend', 'stable') == 'declining':
            risk_score += 25
            risk_factors.append('Declining productivity')
        
        # Check resource availability
        if project_data.get('available_workers', 100) < 60:
            risk_score += 20
            risk_factors.append('Low worker availability')
        
        # Check time remaining vs tasks remaining
        if project_data.get('days_remaining', 100) / max(project_data.get('tasks_remaining', 1), 1) < 2:
            risk_score += 25
            risk_factors.append('Tight schedule with tasks remaining')
        
        # Determine risk level
        if risk_score >= 70:
            risk_level = 'High'
        elif risk_score >= 40:
            risk_level = 'Medium'
        else:
            risk_level = 'Low'
        
        return {
            'risk_score': risk_score,
            'risk_level': risk_level,
            'risk_factors': risk_factors,
            'days_until_deadline': project_data.get('days_remaining', 0),
        }
