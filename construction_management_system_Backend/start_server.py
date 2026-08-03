#!/usr/bin/env python3
"""
简单的服务器启动测试脚本
"""

import sys
import os

def main():
    print("=" * 60)
    print("BuildSmart API Server - 启动测试")
    print("=" * 60)
    
    # 尝试导入 FastAPI 应用
    try:
        from app.main import app
        print("✓ FastAPI 应用导入成功")
    except Exception as e:
        print(f"✗ FastAPI 应用导入失败: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    # 检查数据库表
    try:
        from app.database import SessionLocal
        from app import models
        db = SessionLocal()
        
        # 检查几个关键的新表
        tables_to_check = [
            ('File', models.File),
            ('AIChatSession', models.AIChatSession),
            ('Notification', models.Notification),
        ]
        
        all_good = True
        for name, model in tables_to_check:
            try:
                count = db.query(model).count()
                print(f"✓ {name} 表正常，当前记录数: {count}")
            except Exception as e:
                print(f"✗ {name} 表检查失败: {e}")
                all_good = False
        
        db.close()
        
        if not all_good:
            return 1
            
    except Exception as e:
        print(f"✗ 数据库检查失败: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    print("\n" + "=" * 60)
    print("所有检查通过！")
    print("=" * 60)
    print("\n现在可以启动服务器:")
    print("  uvicorn app.main:app --reload")
    print("\n启动后访问 API 文档:")
    print("  http://localhost:8000/docs")
    print("\n默认登录账号:")
    print("  Email: admin@buildsmart.com")
    print("  Password: admin123")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
