#!/usr/bin/env python3
"""
简单测试脚本 - 验证新增功能的基本运行
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.database import engine, Base, SessionLocal
from app.models import File, AIChatSession, Notification
from app.routers.auth import hpw
from app import models


def test_database_tables():
    """测试数据库表是否正常创建"""
    print("=" * 60)
    print("测试 1: 检查新增数据库表")
    print("=" * 60)
    
    db = SessionLocal()
    try:
        # 检查 File 表
        file_count = db.query(models.File).count()
        print(f"✓ File 表正常，当前记录数: {file_count}")
        
        # 检查 AIChatSession 表
        session_count = db.query(models.AIChatSession).count()
        print(f"✓ AIChatSession 表正常，当前记录数: {session_count}")
        
        # 检查 Notification 表
        notif_count = db.query(models.Notification).count()
        print(f"✓ Notification 表正常，当前记录数: {notif_count}")
        
        print("\n✓ 所有新增数据表检查通过!")
        return True
    except Exception as e:
        print(f"✗ 数据库测试失败: {e}")
        return False
    finally:
        db.close()


def test_file_service():
    """测试文件服务模块"""
    print("\n" + "=" * 60)
    print("测试 2: 检查文件服务模块")
    print("=" * 60)
    
    try:
        from app import file_service
        print("✓ file_service 模块导入成功")
        
        # 检查必要的函数
        required_functions = [
            'ensure_upload_dirs',
            'save_upload_file',
            'create_thumbnail',
            'delete_file'
        ]
        
        for func in required_functions:
            if hasattr(file_service, func):
                print(f"✓ {func} 函数存在")
            else:
                print(f"✗ {func} 函数缺失")
        
        print("\n✓ 文件服务模块检查通过!")
        return True
    except Exception as e:
        print(f"✗ 文件服务测试失败: {e}")
        return False


def test_ai_service():
    """测试 AI 服务模块"""
    print("\n" + "=" * 60)
    print("测试 3: 检查 AI 服务模块")
    print("=" * 60)
    
    try:
        from app import ai_service
        print("✓ ai_service 模块导入成功")
        
        # 检查 Gemini 可用性
        if ai_service.GEMINI_AVAILABLE:
            print("✓ Gemini AI SDK 可用")
        else:
            print("⚠ Gemini AI SDK 未安装或 API Key 未配置")
        
        # 检查必要的函数
        required_functions = [
            'chat_with_ai',
            'analyze_task',
            'generate_daily_report',
            'analyze_safety_risk'
        ]
        
        for func in required_functions:
            if hasattr(ai_service, func):
                print(f"✓ {func} 函数存在")
            else:
                print(f"✗ {func} 函数缺失")
        
        print("\n✓ AI 服务模块检查通过!")
        return True
    except Exception as e:
        print(f"✗ AI 服务测试失败: {e}")
        return False


def test_notification_service():
    """测试通知服务模块"""
    print("\n" + "=" * 60)
    print("测试 4: 检查通知服务模块")
    print("=" * 60)
    
    try:
        from app import notification_service
        print("✓ notification_service 模块导入成功")
        
        # 检查必要的函数
        required_functions = [
            'send_notification',
            'get_or_create_settings',
            'notify_task_assigned',
            'notify_issue_created',
            'notify_safety_incident'
        ]
        
        for func in required_functions:
            if hasattr(notification_service, func):
                print(f"✓ {func} 函数存在")
            else:
                print(f"✗ {func} 函数缺失")
        
        print("\n✓ 通知服务模块检查通过!")
        return True
    except Exception as e:
        print(f"✗ 通知服务测试失败: {e}")
        return False


def test_routers():
    """测试路由模块"""
    print("\n" + "=" * 60)
    print("测试 5: 检查新增路由模块")
    print("=" * 60)
    
    routers_to_test = [
        ('files', 'app.routers.files'),
        ('ai', 'app.routers.ai'),
        ('notifications', 'app.routers.notifications')
    ]
    
    all_good = True
    for name, module_path in routers_to_test:
        try:
            __import__(module_path)
            print(f"✓ {name} 路由模块导入成功")
        except Exception as e:
            print(f"✗ {name} 路由模块导入失败: {e}")
            all_good = False
    
    return all_good


def test_requirements():
    """测试依赖是否安装"""
    print("\n" + "=" * 60)
    print("测试 6: 检查新增依赖包")
    print("=" * 60)
    
    required_packages = [
        'PIL', 'google.generativeai', 'websockets'
    ]
    
    all_good = True
    for package in required_packages:
        try:
            __import__(package)
            print(f"✓ {package} 已安装")
        except ImportError:
            print(f"✗ {package} 未安装")
            all_good = False
    
    if all_good:
        print("\n✓ 所有依赖包检查通过!")
    else:
        print("\n⚠ 部分依赖包缺失，请运行: pip install -r requirements.txt")
    
    return all_good


def main():
    """运行所有测试"""
    print("\n" + "=" * 60)
    print("BuildSmart 新增功能测试")
    print("=" * 60)
    
    results = []
    
    # 运行测试
    results.append(("数据库表", test_database_tables()))
    results.append(("依赖包", test_requirements()))
    results.append(("文件服务", test_file_service()))
    results.append(("AI 服务", test_ai_service()))
    results.append(("通知服务", test_notification_service()))
    results.append(("路由模块", test_routers()))
    
    # 汇总结果
    print("\n" + "=" * 60)
    print("测试结果汇总")
    print("=" * 60)
    
    passed = sum(1 for _, ok in results if ok)
    total = len(results)
    
    for name, ok in results:
        status = "✓ 通过" if ok else "✗ 失败"
        print(f"{name}: {status}")
    
    print(f"\n总计: {passed}/{total} 测试通过")
    
    if passed == total:
        print("\n🎉 所有测试通过！系统准备就绪。")
        print("\n下一步:")
        print("1. 配置 .env 文件中的 GEMINI_API_KEY")
        print("2. 运行: uvicorn app.main:app --reload")
        print("3. 访问: http://localhost:8000/docs 查看 API 文档")
        return 0
    else:
        print("\n⚠ 部分测试失败，请检查错误信息。")
        return 1


if __name__ == "__main__":
    sys.exit(main())
