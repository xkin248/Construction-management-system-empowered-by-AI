import React, { useState } from 'react';

interface Task {
  id: string;
  title: string;
  project: string;
  priority: 'High' | 'Medium' | 'Low';
  progress: number;
  assignee: string;
  dueDate: string;
  status: 'In Progress' | 'Completed' | 'Pending';
}

const TaskManagement: React.FC = () => {
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);

  const tasks: Task[] = [
    {
      id: '1',
      title: 'Foundation Pile Driving - Block B',
      project: 'Kuala Lumpur Tower Block A',
      priority: 'High',
      progress: 65,
      assignee: 'Ahmad Zulkifli',
      dueDate: '2025-05-20',
      status: 'In Progress'
    },
    {
      id: '2',
      title: '3rd Floor Electrical Conduit Installation',
      project: 'Kuala Lumpur Tower Block A',
      priority: 'High',
      progress: 40,
      assignee: 'Boon Chong Tan',
      dueDate: '2025-05-18',
      status: 'In Progress'
    },
    {
      id: '3',
      title: 'Scaffolding Setup - West Facade',
      project: 'Kuala Lumpur Tower Block A',
      priority: 'Medium',
      progress: 100,
      assignee: 'Rajesh Kumar',
      dueDate: '2025-05-10',
      status: 'Completed'
    },
    {
      id: '4',
      title: 'Structural Steel Beam Welding - Level 5',
      project: 'Kuala Lumpur Tower Block A',
      priority: 'High',
      progress: 30,
      assignee: 'TBD',
      dueDate: '2025-05-25',
      status: 'In Progress'
    }
  ];

  const taskStats = [
    { label: 'In Progress', count: 6, color: 'text-blue-600' },
    { label: 'Completed', count: 2, color: 'text-green-600' },
    { label: 'Pending', count: 2, color: 'text-yellow-600' }
  ];

  const getPriorityColor = (priority: string) => {
    switch (priority) {
      case 'High':
        return 'text-red-600 bg-red-50';
      case 'Medium':
        return 'text-yellow-600 bg-yellow-50';
      case 'Low':
        return 'text-blue-600 bg-blue-50';
      default:
        return 'text-gray-600 bg-gray-50';
    }
  };

  const getProgressColor = (progress: number) => {
    if (progress >= 75) return 'bg-green-500';
    if (progress >= 50) return 'bg-blue-500';
    if (progress >= 25) return 'bg-yellow-500';
    return 'bg-red-500';
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 px-8 py-6 flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Task Management</h1>
          <p className="text-gray-600 mt-1">10 tasks across all projects</p>
        </div>
        <button className="bg-orange-500 text-white px-6 py-2 rounded-lg font-semibold hover:bg-orange-600">
          + New Task
        </button>
      </div>

      {/* Main Content */}
      <div className="p-8">
        {/* Task Stats */}
        <div className="grid grid-cols-3 gap-6 mb-8">
          {taskStats.map((stat) => (
            <div key={stat.label} className="bg-white rounded-lg shadow p-6 text-center">
              <p className={`text-4xl font-bold ${stat.color}`}>{stat.count}</p>
              <p className="text-gray-600 mt-2">{stat.label}</p>
            </div>
          ))}
        </div>

        {/* Filters and Task List */}
        <div className="grid grid-cols-3 gap-8">
          {/* Tasks List */}
          <div className="col-span-2 bg-white rounded-lg shadow p-6">
            {/* Search and Filters */}
            <div className="mb-6">
              <input
                type="text"
                placeholder="Search tasks..."
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500"
              />
            </div>

            <div className="flex gap-4 mb-6">
              <select className="px-4 py-2 border border-gray-300 rounded-lg focus:outline-none">
                <option>All Status</option>
              </select>
              <select className="px-4 py-2 border border-gray-300 rounded-lg focus:outline-none">
                <option>All Projects</option>
              </select>
              <select className="px-4 py-2 border border-gray-300 rounded-lg focus:outline-none">
                <option>All Priority</option>
              </select>
            </div>

            {/* Tasks */}
            <div className="space-y-4">
              {tasks.map((task) => (
                <div
                  key={task.id}
                  onClick={() => setSelectedTask(task)}
                  className={`border-l-4 p-4 rounded cursor-pointer hover:bg-gray-50 transition ${
                    task.priority === 'High' ? 'border-l-orange-500 bg-orange-50' : 'border-l-gray-200 bg-white'
                  }`}
                >
                  <div className="flex justify-between items-start mb-3">
                    <div>
                      <h3 className="font-semibold text-gray-900">{task.title}</h3>
                      <p className="text-sm text-gray-600">{task.project}</p>
                    </div>
                    <span className={`px-3 py-1 rounded-full text-sm font-semibold ${getPriorityColor(task.priority)}`}>
                      {task.priority}
                    </span>
                  </div>
                  <div className="flex items-center justify-between">
                    <div className="flex-1 bg-gray-200 rounded-full h-2 mr-4">
                      <div className={`${getProgressColor(task.progress)} h-2 rounded-full`} style={{ width: `${task.progress}%` }}></div>
                    </div>
                    <span className="text-sm font-semibold text-gray-900">{task.progress}%</span>
                  </div>
                  <div className="flex items-center gap-4 mt-3 text-sm text-gray-600">
                    <span>👤 {task.assignee}</span>
                    <span>📅 {task.dueDate}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Task Details Panel */}
          {selectedTask && (
            <div className="bg-gray-900 text-white rounded-lg shadow p-6">
              <div className="flex justify-between items-center mb-6">
                <h2 className="text-xl font-bold">Task Details</h2>
                <span className="bg-blue-500 text-white px-3 py-1 rounded-full text-sm">In Progress</span>
              </div>

              <h3 className="font-bold text-lg mb-4">{selectedTask.title}</h3>
              <p className="text-gray-400 text-sm mb-6">{selectedTask.project}</p>

              <div className="space-y-4">
                <div>
                  <p className="text-gray-400 text-sm mb-1">Priority</p>
                  <p className={`font-semibold ${selectedTask.priority === 'High' ? 'text-red-500' : 'text-gray-200'}`}>
                    🚩 {selectedTask.priority}
                  </p>
                </div>

                <div>
                  <p className="text-gray-400 text-sm mb-2">Task Progress</p>
                  <div className="bg-gray-700 rounded-full h-2">
                    <div className="bg-blue-500 h-2 rounded-full" style={{ width: `${selectedTask.progress}%` }}></div>
                  </div>
                  <p className="text-right mt-2 text-gray-400 text-sm">{selectedTask.progress}%</p>
                </div>

                <div className="grid grid-cols-2 gap-4 mt-6">
                  <div>
                    <p className="text-gray-400 text-sm">Logged</p>
                    <p className="font-bold text-xl">52h</p>
                  </div>
                  <div>
                    <p className="text-gray-400 text-sm">Estimated</p>
                    <p className="font-bold text-xl">80h</p>
                  </div>
                </div>

                <div>
                  <p className="text-gray-400 text-sm mb-1">Due Date</p>
                  <p className="font-semibold">📅 {selectedTask.dueDate}</p>
                </div>

                <div>
                  <p className="text-gray-400 text-sm mb-3">Assigned To</p>
                  <div className="bg-orange-500 rounded-lg p-3 text-center">
                    <p className="font-bold text-lg">AZ</p>
                    <p className="text-sm font-semibold">{selectedTask.assignee}</p>
                    <p className="text-xs mt-1">Heavy Equipment Operator</p>
                    <p className="text-sm mt-2">⭐ 4.4</p>
                  </div>
                </div>

                <div>
                  <p className="text-gray-400 text-sm mb-2">Required Skills</p>
                  <div className="flex gap-2 flex-wrap">
                    <span className="px-3 py-1 bg-gray-700 rounded text-sm">Heavy Equipment</span>
                    <span className="px-3 py-1 bg-gray-700 rounded text-sm">Foundation Work</span>
                  </div>
                </div>

                <div className="bg-purple-900 bg-opacity-50 rounded-lg p-3 mt-6">
                  <p className="text-purple-300 text-sm mb-1">AI Match Score</p>
                  <p className="text-purple-300 font-bold text-2xl">94%</p>
                  <p className="text-purple-400 text-xs mt-1">Optimal worker-task alignment</p>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default TaskManagement;